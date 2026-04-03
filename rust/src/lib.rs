use std::cell::RefCell;
use std::collections::VecDeque;
use std::ffi::{c_char, c_void, CStr, CString};
use std::fs::File;
use std::io::{BufReader, Read, Write};
use std::panic::{self, AssertUnwindSafe};
use std::path::PathBuf;
use std::ptr;
use std::slice;

use calamine::{DataRef, Reader, ReaderRef, Xlsx};
use rust_xlsxwriter::{Workbook, Worksheet, XlsxError};
use tempfile::{Builder, NamedTempFile, TempDir};

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FxStatus {
    Ok = 0,
    Done = 1,
    InvalidArgument = 2,
    IoError = 3,
    XlsxError = 4,
    Utf8Error = 5,
    InternalError = 6,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FxCellType {
    Blank = 0,
    Int = 1,
    Double = 2,
    Bool = 3,
    Text = 4,
    DateText = 5,
    Error = 6,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct FxCellValue {
    pub cell_type: u32,
    pub int_value: i64,
    pub double_value: f64,
    pub bool_value: bool,
    pub string_value: *const c_char,
}

thread_local! {
    static LAST_ERROR: RefCell<CString> = RefCell::new(CString::default());
}

const HANDLE_UPLOAD: u32 = 1;
const HANDLE_READER: u32 = 2;
const HANDLE_ROW: u32 = 3;
const HANDLE_WRITER: u32 = 4;
const HANDLE_OUTPUT: u32 = 5;

#[repr(C)]
struct HandleBase {
    kind: u32,
    last_error: CString,
}

impl HandleBase {
    fn new(kind: u32) -> Self {
        Self {
            kind,
            last_error: CString::default(),
        }
    }

    fn set_error(&mut self, message: impl AsRef<str>) {
        self.last_error = to_cstring(message.as_ref());
    }
}

trait HasHandleBase {
    fn base_mut(&mut self) -> &mut HandleBase;
}

#[derive(Debug)]
struct FxError {
    status: FxStatus,
    message: String,
}

impl FxError {
    fn new(status: FxStatus, message: impl Into<String>) -> Self {
        Self {
            status,
            message: message.into(),
        }
    }
}

impl From<std::io::Error> for FxError {
    fn from(value: std::io::Error) -> Self {
        Self::new(FxStatus::IoError, value.to_string())
    }
}

impl From<calamine::XlsxError> for FxError {
    fn from(value: calamine::XlsxError) -> Self {
        Self::new(FxStatus::XlsxError, value.to_string())
    }
}

impl From<XlsxError> for FxError {
    fn from(value: XlsxError) -> Self {
        Self::new(FxStatus::XlsxError, value.to_string())
    }
}

impl From<std::str::Utf8Error> for FxError {
    fn from(value: std::str::Utf8Error) -> Self {
        Self::new(FxStatus::Utf8Error, value.to_string())
    }
}

#[derive(Debug, Clone)]
enum OwnedCell {
    Blank,
    Int(i64),
    Double(f64),
    Bool(bool),
    Text(String),
    DateText(String),
    Error(String),
}

#[derive(Debug, Clone)]
struct OwnedRow {
    row_index: u64,
    cells: Vec<OwnedCell>,
}

trait SheetRowReader: Send {
    fn sheet_name(&self) -> &CStr;
    fn next_row(&mut self) -> Result<Option<OwnedRow>, FxError>;
}

struct CalamineSheetReader {
    sheet_name: CString,
    rows: VecDeque<OwnedRow>,
}

impl CalamineSheetReader {
    fn open(file: &File) -> Result<Self, FxError> {
        let workbook_file = file.try_clone()?;
        let mut workbook: Xlsx<_> = Xlsx::new(BufReader::new(workbook_file))?;
        let sheet_names = workbook.sheet_names().to_vec();
        let sheet_name = sheet_names
            .first()
            .ok_or_else(|| FxError::new(FxStatus::XlsxError, "Workbook has no worksheets"))?
            .clone();

        let range = workbook
            .worksheet_range_at_ref(0)
            .ok_or_else(|| FxError::new(FxStatus::XlsxError, "Workbook has no worksheets"))??;

        let row_offset = range.start().map(|(row, _)| row as u64).unwrap_or(0);
        let mut rows = VecDeque::new();

        for (offset, row) in range.rows().enumerate() {
            let mut cells = row.iter().map(map_data_ref).collect::<Vec<_>>();
            trim_trailing_blanks(&mut cells);
            if cells.is_empty() {
                continue;
            }
            rows.push_back(OwnedRow {
                row_index: row_offset + offset as u64,
                cells,
            });
        }

        Ok(Self {
            sheet_name: to_cstring(&sheet_name),
            rows,
        })
    }
}

impl SheetRowReader for CalamineSheetReader {
    fn sheet_name(&self) -> &CStr {
        self.sheet_name.as_c_str()
    }

    fn next_row(&mut self) -> Result<Option<OwnedRow>, FxError> {
        Ok(self.rows.pop_front())
    }
}

#[repr(C)]
pub struct FxUploadHandle {
    base: HandleBase,
    temp_file: NamedTempFile,
}

impl HasHandleBase for FxUploadHandle {
    fn base_mut(&mut self) -> &mut HandleBase {
        &mut self.base
    }
}

#[repr(C)]
pub struct FxReaderHandle {
    base: HandleBase,
    engine: Box<dyn SheetRowReader>,
}

impl HasHandleBase for FxReaderHandle {
    fn base_mut(&mut self) -> &mut HandleBase {
        &mut self.base
    }
}

#[repr(C)]
pub struct FxRowHandle {
    base: HandleBase,
    row: OwnedRow,
    strings: Vec<Option<CString>>,
}

impl HasHandleBase for FxRowHandle {
    fn base_mut(&mut self) -> &mut HandleBase {
        &mut self.base
    }
}

#[repr(C)]
pub struct FxWriterHandle {
    base: HandleBase,
    temp_dir: TempDir,
    workbook: Workbook,
    worksheet: Option<Worksheet>,
    next_row_index: u32,
}

impl HasHandleBase for FxWriterHandle {
    fn base_mut(&mut self) -> &mut HandleBase {
        &mut self.base
    }
}

#[repr(C)]
pub struct FxOutputHandle {
    base: HandleBase,
    temp_dir: TempDir,
    file_path: PathBuf,
    reader: BufReader<File>,
}

impl HasHandleBase for FxOutputHandle {
    fn base_mut(&mut self) -> &mut HandleBase {
        &mut self.base
    }
}

fn to_cstring(value: &str) -> CString {
    let sanitized = value.replace('\0', " ");
    CString::new(sanitized).unwrap_or_default()
}

fn set_global_error(message: impl AsRef<str>) {
    LAST_ERROR.with(|slot| {
        *slot.borrow_mut() = to_cstring(message.as_ref());
    });
}

fn set_handle_error<T: HasHandleBase>(handle: &mut T, error: &FxError) -> FxStatus {
    handle.base_mut().set_error(&error.message);
    error.status
}

fn map_data_ref(data: &DataRef<'_>) -> OwnedCell {
    match data {
        DataRef::Empty => OwnedCell::Blank,
        DataRef::Int(value) => OwnedCell::Int(*value),
        DataRef::Float(value) => {
            if value.is_finite()
                && value.fract() == 0.0
                && *value >= i64::MIN as f64
                && *value <= i64::MAX as f64
            {
                OwnedCell::Int(*value as i64)
            } else {
                OwnedCell::Double(*value)
            }
        }
        DataRef::Bool(value) => OwnedCell::Bool(*value),
        DataRef::String(value) => OwnedCell::Text(value.to_string()),
        DataRef::SharedString(value) => OwnedCell::Text(value.to_string()),
        DataRef::DateTime(value) => OwnedCell::DateText(value.to_string()),
        DataRef::DateTimeIso(value) => OwnedCell::DateText(value.to_string()),
        DataRef::DurationIso(value) => OwnedCell::DateText(value.to_string()),
        DataRef::Error(value) => OwnedCell::Error(value.to_string()),
    }
}

fn trim_trailing_blanks(cells: &mut Vec<OwnedCell>) {
    while matches!(cells.last(), Some(OwnedCell::Blank)) {
        cells.pop();
    }
}

fn build_row_handle(row: OwnedRow) -> FxRowHandle {
    let strings = row
        .cells
        .iter()
        .map(|cell| match cell {
            OwnedCell::Text(value) | OwnedCell::DateText(value) | OwnedCell::Error(value) => {
                Some(to_cstring(value))
            }
            _ => None,
        })
        .collect();

    FxRowHandle {
        base: HandleBase::new(HANDLE_ROW),
        row,
        strings,
    }
}

fn writer_from_sheet_name(sheet_name: &str) -> Result<FxWriterHandle, FxError> {
    let temp_dir = Builder::new().prefix("fast_xlsx_writer").tempdir()?;
    let mut workbook = Workbook::new();
    workbook.set_tempdir(temp_dir.path())?;
    let mut worksheet = workbook.new_worksheet_with_constant_memory();
    worksheet.set_name(sheet_name)?;

    Ok(FxWriterHandle {
        base: HandleBase::new(HANDLE_WRITER),
        temp_dir,
        workbook,
        worksheet: Some(worksheet),
        next_row_index: 0,
    })
}

fn output_from_writer(
    mut writer: FxWriterHandle,
) -> Result<FxOutputHandle, (FxWriterHandle, FxError)> {
    let worksheet = match writer.worksheet.take() {
        Some(worksheet) => worksheet,
        None => {
            return Err((
                writer,
                FxError::new(
                    FxStatus::InternalError,
                    "Writer workbook was already finalized",
                ),
            ))
        }
    };

    writer.workbook.push_worksheet(worksheet);
    let file_path = writer.temp_dir.path().join("output.xlsx");
    if let Err(error) = writer.workbook.save(&file_path) {
        return Err((writer, error.into()));
    }

    let file = match File::open(&file_path) {
        Ok(file) => file,
        Err(error) => return Err((writer, error.into())),
    };

    Ok(FxOutputHandle {
        base: HandleBase::new(HANDLE_OUTPUT),
        temp_dir: writer.temp_dir,
        file_path,
        reader: BufReader::new(file),
    })
}

fn with_panic_status(default: FxStatus, action: impl FnOnce() -> FxStatus) -> FxStatus {
    match panic::catch_unwind(AssertUnwindSafe(action)) {
        Ok(status) => status,
        Err(_) => {
            set_global_error("Rust panic crossed the FFI boundary");
            default
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn fx_begin_upload(out_handle: *mut *mut FxUploadHandle) -> FxStatus {
    with_panic_status(FxStatus::InternalError, || {
        if out_handle.is_null() {
            set_global_error("Output handle pointer is null");
            return FxStatus::InvalidArgument;
        }

        match Builder::new().prefix("fast_xlsx_upload").tempfile() {
            Ok(temp_file) => {
                let handle = FxUploadHandle {
                    base: HandleBase::new(HANDLE_UPLOAD),
                    temp_file,
                };
                *out_handle = Box::into_raw(Box::new(handle));
                FxStatus::Ok
            }
            Err(error) => {
                set_global_error(error.to_string());
                FxStatus::IoError
            }
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn fx_upload_write_chunk(
    handle: *mut FxUploadHandle,
    data: *const u8,
    len: usize,
) -> FxStatus {
    with_panic_status(FxStatus::InternalError, || {
        if handle.is_null() {
            set_global_error("Upload handle is null");
            return FxStatus::InvalidArgument;
        }
        if len > 0 && data.is_null() {
            let upload = &mut *handle;
            return set_handle_error(
                upload,
                &FxError::new(FxStatus::InvalidArgument, "Upload chunk pointer is null"),
            );
        }

        let upload = &mut *handle;
        let chunk = slice::from_raw_parts(data, len);
        match upload.temp_file.as_file_mut().write_all(chunk) {
            Ok(()) => FxStatus::Ok,
            Err(error) => set_handle_error(upload, &error.into()),
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn fx_upload_finish_open_reader(
    handle: *mut FxUploadHandle,
    out_reader: *mut *mut FxReaderHandle,
) -> FxStatus {
    with_panic_status(FxStatus::InternalError, || {
        if handle.is_null() || out_reader.is_null() {
            set_global_error("Upload handle or reader output pointer is null");
            return FxStatus::InvalidArgument;
        }

        let mut upload = Box::from_raw(handle);
        let status = match upload.temp_file.as_file_mut().flush() {
            Ok(()) => match CalamineSheetReader::open(upload.temp_file.as_file()) {
                Ok(reader) => {
                    let reader_handle = FxReaderHandle {
                        base: HandleBase::new(HANDLE_READER),
                        engine: Box::new(reader),
                    };
                    *out_reader = Box::into_raw(Box::new(reader_handle));
                    FxStatus::Ok
                }
                Err(error) => {
                    let status = set_handle_error(upload.as_mut(), &error);
                    let _ = Box::into_raw(upload);
                    status
                }
            },
            Err(error) => {
                let fx_error: FxError = error.into();
                let status = set_handle_error(upload.as_mut(), &fx_error);
                let _ = Box::into_raw(upload);
                status
            }
        };

        if status == FxStatus::Ok {
            status
        } else {
            status
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn fx_upload_close(handle: *mut FxUploadHandle) {
    let _ = panic::catch_unwind(AssertUnwindSafe(|| {
        if !handle.is_null() {
            drop(Box::from_raw(handle));
        }
    }));
}

#[no_mangle]
pub unsafe extern "C" fn fx_reader_sheet_name(
    handle: *const FxReaderHandle,
    out_name: *mut *const c_char,
) -> FxStatus {
    with_panic_status(FxStatus::InternalError, || {
        if handle.is_null() || out_name.is_null() {
            set_global_error("Reader handle or output name pointer is null");
            return FxStatus::InvalidArgument;
        }

        let reader = &*handle;
        *out_name = reader.engine.sheet_name().as_ptr();
        FxStatus::Ok
    })
}

#[no_mangle]
pub unsafe extern "C" fn fx_reader_next_row(
    handle: *mut FxReaderHandle,
    out_row: *mut *mut FxRowHandle,
) -> FxStatus {
    with_panic_status(FxStatus::InternalError, || {
        if handle.is_null() || out_row.is_null() {
            set_global_error("Reader handle or output row pointer is null");
            return FxStatus::InvalidArgument;
        }

        let reader = &mut *handle;
        match reader.engine.next_row() {
            Ok(Some(row)) => {
                *out_row = Box::into_raw(Box::new(build_row_handle(row)));
                FxStatus::Ok
            }
            Ok(None) => {
                *out_row = ptr::null_mut();
                FxStatus::Done
            }
            Err(error) => set_handle_error(reader, &error),
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn fx_reader_close(handle: *mut FxReaderHandle) {
    let _ = panic::catch_unwind(AssertUnwindSafe(|| {
        if !handle.is_null() {
            drop(Box::from_raw(handle));
        }
    }));
}

#[no_mangle]
pub unsafe extern "C" fn fx_row_len(handle: *const FxRowHandle) -> usize {
    if handle.is_null() {
        return 0;
    }
    (*handle).row.cells.len()
}

#[no_mangle]
pub unsafe extern "C" fn fx_row_index(handle: *const FxRowHandle) -> u64 {
    if handle.is_null() {
        return 0;
    }
    (*handle).row.row_index
}

#[no_mangle]
pub unsafe extern "C" fn fx_row_cell_type(handle: *const FxRowHandle, index: usize) -> FxCellType {
    if handle.is_null() {
        return FxCellType::Blank;
    }

    match (&(*handle).row.cells).get(index) {
        Some(OwnedCell::Blank) => FxCellType::Blank,
        Some(OwnedCell::Int(_)) => FxCellType::Int,
        Some(OwnedCell::Double(_)) => FxCellType::Double,
        Some(OwnedCell::Bool(_)) => FxCellType::Bool,
        Some(OwnedCell::Text(_)) => FxCellType::Text,
        Some(OwnedCell::DateText(_)) => FxCellType::DateText,
        Some(OwnedCell::Error(_)) => FxCellType::Error,
        None => FxCellType::Blank,
    }
}

#[no_mangle]
pub unsafe extern "C" fn fx_row_cell_int(handle: *const FxRowHandle, index: usize) -> i64 {
    if handle.is_null() {
        return 0;
    }

    match (&(*handle).row.cells).get(index) {
        Some(OwnedCell::Int(value)) => *value,
        _ => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn fx_row_cell_double(handle: *const FxRowHandle, index: usize) -> f64 {
    if handle.is_null() {
        return 0.0;
    }

    match (&(*handle).row.cells).get(index) {
        Some(OwnedCell::Double(value)) => *value,
        _ => 0.0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn fx_row_cell_bool(handle: *const FxRowHandle, index: usize) -> bool {
    if handle.is_null() {
        return false;
    }

    match (&(*handle).row.cells).get(index) {
        Some(OwnedCell::Bool(value)) => *value,
        _ => false,
    }
}

#[no_mangle]
pub unsafe extern "C" fn fx_row_cell_string(
    handle: *const FxRowHandle,
    index: usize,
) -> *const c_char {
    if handle.is_null() {
        return ptr::null();
    }

    (&(*handle).strings)
        .get(index)
        .and_then(Option::as_ref)
        .map_or(ptr::null(), |value| value.as_ptr())
}

#[no_mangle]
pub unsafe extern "C" fn fx_row_release(handle: *mut FxRowHandle) {
    let _ = panic::catch_unwind(AssertUnwindSafe(|| {
        if !handle.is_null() {
            drop(Box::from_raw(handle));
        }
    }));
}

#[no_mangle]
pub unsafe extern "C" fn fx_writer_open(
    sheet_name: *const c_char,
    out_handle: *mut *mut FxWriterHandle,
) -> FxStatus {
    with_panic_status(FxStatus::InternalError, || {
        if sheet_name.is_null() || out_handle.is_null() {
            set_global_error("Sheet name or writer output pointer is null");
            return FxStatus::InvalidArgument;
        }

        let sheet_name = match CStr::from_ptr(sheet_name).to_str() {
            Ok(value) => value,
            Err(error) => {
                set_global_error(error.to_string());
                return FxStatus::Utf8Error;
            }
        };

        match writer_from_sheet_name(sheet_name) {
            Ok(handle) => {
                *out_handle = Box::into_raw(Box::new(handle));
                FxStatus::Ok
            }
            Err(error) => {
                set_global_error(&error.message);
                error.status
            }
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn fx_writer_add_row(
    handle: *mut FxWriterHandle,
    cells: *const FxCellValue,
    len: usize,
) -> FxStatus {
    with_panic_status(FxStatus::InternalError, || {
        if handle.is_null() {
            set_global_error("Writer handle is null");
            return FxStatus::InvalidArgument;
        }
        if len > 0 && cells.is_null() {
            let writer = &mut *handle;
            return set_handle_error(
                writer,
                &FxError::new(FxStatus::InvalidArgument, "Cell buffer pointer is null"),
            );
        }

        let writer = &mut *handle;
        let worksheet = match writer.worksheet.as_mut() {
            Some(worksheet) => worksheet,
            None => {
                return set_handle_error(
                    writer,
                    &FxError::new(FxStatus::InternalError, "Writer was already finalized"),
                )
            }
        };

        let row_index = writer.next_row_index;
        let native_cells = slice::from_raw_parts(cells, len);

        for (column_index, native_cell) in native_cells.iter().enumerate() {
            let column_index = match u16::try_from(column_index) {
                Ok(value) => value,
                Err(_) => {
                    return set_handle_error(
                        writer,
                        &FxError::new(
                            FxStatus::InvalidArgument,
                            "Column index exceeded XLSX limits",
                        ),
                    )
                }
            };

            let result: Result<(), XlsxError> = match native_cell.cell_type {
                x if x == FxCellType::Blank as u32 => Ok(()),
                x if x == FxCellType::Int as u32 => worksheet
                    .write(row_index, column_index, native_cell.int_value)
                    .map(|_| ()),
                x if x == FxCellType::Double as u32 => worksheet
                    .write(row_index, column_index, native_cell.double_value)
                    .map(|_| ()),
                x if x == FxCellType::Bool as u32 => worksheet
                    .write(row_index, column_index, native_cell.bool_value)
                    .map(|_| ()),
                x if x == FxCellType::Text as u32
                    || x == FxCellType::DateText as u32
                    || x == FxCellType::Error as u32 =>
                {
                    if native_cell.string_value.is_null() {
                        Err(XlsxError::ParameterError(
                            "String cell pointer cannot be null".to_string(),
                        ))
                    } else {
                        match CStr::from_ptr(native_cell.string_value).to_str() {
                            Ok(value) => worksheet
                                .write_string(row_index, column_index, value)
                                .map(|_| ()),
                            Err(error) => return set_handle_error(writer, &FxError::from(error)),
                        }
                    }
                }
                _ => {
                    return set_handle_error(
                        writer,
                        &FxError::new(FxStatus::InvalidArgument, "Unknown cell type tag"),
                    )
                }
            };

            if let Err(error) = result {
                let fx_error: FxError = error.into();
                return set_handle_error(writer, &fx_error);
            }
        }

        writer.next_row_index = match writer.next_row_index.checked_add(1) {
            Some(value) => value,
            None => {
                return set_handle_error(
                    writer,
                    &FxError::new(FxStatus::XlsxError, "Worksheet row limit exceeded"),
                )
            }
        };

        FxStatus::Ok
    })
}

#[no_mangle]
pub unsafe extern "C" fn fx_writer_finish_open_output(
    handle: *mut FxWriterHandle,
    out_output: *mut *mut FxOutputHandle,
) -> FxStatus {
    with_panic_status(FxStatus::InternalError, || {
        if handle.is_null() || out_output.is_null() {
            set_global_error("Writer handle or output pointer is null");
            return FxStatus::InvalidArgument;
        }

        let writer = Box::from_raw(handle);
        match output_from_writer(*writer) {
            Ok(output) => {
                *out_output = Box::into_raw(Box::new(output));
                FxStatus::Ok
            }
            Err((writer_handle, error)) => {
                let mut writer = Box::new(writer_handle);
                let status = set_handle_error(writer.as_mut(), &error);
                let _ = Box::into_raw(writer);
                status
            }
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn fx_writer_close(handle: *mut FxWriterHandle) {
    let _ = panic::catch_unwind(AssertUnwindSafe(|| {
        if !handle.is_null() {
            drop(Box::from_raw(handle));
        }
    }));
}

#[no_mangle]
pub unsafe extern "C" fn fx_output_read_chunk(
    handle: *mut FxOutputHandle,
    buffer: *mut u8,
    capacity: usize,
    out_len: *mut usize,
) -> FxStatus {
    with_panic_status(FxStatus::InternalError, || {
        if handle.is_null() || buffer.is_null() || out_len.is_null() {
            set_global_error("Output handle, buffer, or length pointer is null");
            return FxStatus::InvalidArgument;
        }
        if capacity == 0 {
            let output = &mut *handle;
            return set_handle_error(
                output,
                &FxError::new(
                    FxStatus::InvalidArgument,
                    "Chunk buffer capacity must be > 0",
                ),
            );
        }

        let output = &mut *handle;
        let target = slice::from_raw_parts_mut(buffer, capacity);
        match output.reader.read(target) {
            Ok(0) => {
                *out_len = 0;
                FxStatus::Done
            }
            Ok(count) => {
                *out_len = count;
                FxStatus::Ok
            }
            Err(error) => set_handle_error(output, &error.into()),
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn fx_output_close(handle: *mut FxOutputHandle) {
    let _ = panic::catch_unwind(AssertUnwindSafe(|| {
        if !handle.is_null() {
            drop(Box::from_raw(handle));
        }
    }));
}

#[no_mangle]
pub unsafe extern "C" fn fx_error_message(handle: *const c_void) -> *const c_char {
    if handle.is_null() {
        return LAST_ERROR.with(|slot| slot.borrow().as_ptr());
    }

    let base = &*(handle.cast::<HandleBase>());
    base.last_error.as_ptr()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn collect_output(output: *mut FxOutputHandle) -> Vec<u8> {
        let mut bytes = Vec::new();
        let mut buffer = vec![0_u8; 1024];
        loop {
            let mut count = 0usize;
            let status = unsafe {
                fx_output_read_chunk(output, buffer.as_mut_ptr(), buffer.len(), &mut count)
            };
            match status {
                FxStatus::Ok => bytes.extend_from_slice(&buffer[..count]),
                FxStatus::Done => break,
                other => panic!("unexpected output read status: {other:?}"),
            }
        }
        unsafe {
            fx_output_close(output);
        }
        bytes
    }

    #[test]
    fn ffi_round_trip_read_write() {
        let mut writer = ptr::null_mut();
        let status = unsafe { fx_writer_open(to_cstring("Sheet1").as_ptr(), &mut writer) };
        assert_eq!(status, FxStatus::Ok);

        let row1 = [
            FxCellValue {
                cell_type: FxCellType::Text as u32,
                int_value: 0,
                double_value: 0.0,
                bool_value: false,
                string_value: to_cstring("name").into_raw(),
            },
            FxCellValue {
                cell_type: FxCellType::Int as u32,
                int_value: 42,
                double_value: 0.0,
                bool_value: false,
                string_value: ptr::null(),
            },
        ];
        let status = unsafe { fx_writer_add_row(writer, row1.as_ptr(), row1.len()) };
        assert_eq!(status, FxStatus::Ok);

        let mut output = ptr::null_mut();
        let status = unsafe { fx_writer_finish_open_output(writer, &mut output) };
        assert_eq!(status, FxStatus::Ok);

        let bytes = collect_output(output);

        let mut upload = ptr::null_mut();
        let status = unsafe { fx_begin_upload(&mut upload) };
        assert_eq!(status, FxStatus::Ok);
        let status = unsafe { fx_upload_write_chunk(upload, bytes.as_ptr(), bytes.len()) };
        assert_eq!(status, FxStatus::Ok);

        let mut reader = ptr::null_mut();
        let status = unsafe { fx_upload_finish_open_reader(upload, &mut reader) };
        assert_eq!(status, FxStatus::Ok);

        let mut row = ptr::null_mut();
        let status = unsafe { fx_reader_next_row(reader, &mut row) };
        assert_eq!(status, FxStatus::Ok);
        assert_eq!(unsafe { fx_row_index(row) }, 0);
        assert_eq!(unsafe { fx_row_len(row) }, 2);
        assert_eq!(unsafe { fx_row_cell_type(row, 0) }, FxCellType::Text);
        assert_eq!(
            unsafe { CStr::from_ptr(fx_row_cell_string(row, 0)).to_str().unwrap() },
            "name"
        );
        assert_eq!(unsafe { fx_row_cell_int(row, 1) }, 42);

        unsafe {
            fx_row_release(row);
            fx_reader_close(reader);
        }
    }

    #[test]
    fn malformed_upload_returns_xlsx_error() {
        let mut upload = ptr::null_mut();
        assert_eq!(unsafe { fx_begin_upload(&mut upload) }, FxStatus::Ok);
        let bytes = b"not an xlsx";
        assert_eq!(
            unsafe { fx_upload_write_chunk(upload, bytes.as_ptr(), bytes.len()) },
            FxStatus::Ok
        );
        let mut reader = ptr::null_mut();
        let status = unsafe { fx_upload_finish_open_reader(upload, &mut reader) };
        assert_eq!(status, FxStatus::XlsxError);
        unsafe {
            fx_upload_close(upload);
        }
    }
}
