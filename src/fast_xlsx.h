#ifndef FAST_XLSX_H_
#define FAST_XLSX_H_

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct FxUploadHandle FxUploadHandle;
typedef struct FxReaderHandle FxReaderHandle;
typedef struct FxRowHandle FxRowHandle;
typedef struct FxWriterHandle FxWriterHandle;
typedef struct FxOutputHandle FxOutputHandle;

typedef enum FxStatus {
  FX_STATUS_OK = 0,
  FX_STATUS_DONE = 1,
  FX_STATUS_INVALID_ARGUMENT = 2,
  FX_STATUS_IO_ERROR = 3,
  FX_STATUS_XLSX_ERROR = 4,
  FX_STATUS_UTF8_ERROR = 5,
  FX_STATUS_INTERNAL_ERROR = 6
} FxStatus;

typedef enum FxCellType {
  FX_CELL_BLANK = 0,
  FX_CELL_INT = 1,
  FX_CELL_DOUBLE = 2,
  FX_CELL_BOOL = 3,
  FX_CELL_TEXT = 4,
  FX_CELL_DATE_TEXT = 5,
  FX_CELL_ERROR = 6
} FxCellType;

typedef struct FxCellValue {
  uint32_t cell_type;
  int64_t int_value;
  double double_value;
  bool bool_value;
  const char* string_value;
} FxCellValue;

FxStatus fx_begin_upload(FxUploadHandle** out_handle);
FxStatus fx_upload_write_chunk(FxUploadHandle* handle, const uint8_t* data, uintptr_t len);
FxStatus fx_upload_finish_open_reader(FxUploadHandle* handle, FxReaderHandle** out_reader);
void fx_upload_close(FxUploadHandle* handle);

FxStatus fx_reader_open_path(const char* path, FxReaderHandle** out_reader);
FxStatus fx_reader_sheet_name(const FxReaderHandle* handle, const char** out_name);
FxStatus fx_reader_next_row(FxReaderHandle* handle, FxRowHandle** out_row);
void fx_reader_close(FxReaderHandle* handle);

uintptr_t fx_row_len(const FxRowHandle* handle);
uint64_t fx_row_index(const FxRowHandle* handle);
FxCellType fx_row_cell_type(const FxRowHandle* handle, uintptr_t index);
int64_t fx_row_cell_int(const FxRowHandle* handle, uintptr_t index);
double fx_row_cell_double(const FxRowHandle* handle, uintptr_t index);
bool fx_row_cell_bool(const FxRowHandle* handle, uintptr_t index);
const char* fx_row_cell_string(const FxRowHandle* handle, uintptr_t index);
void fx_row_release(FxRowHandle* handle);

FxStatus fx_writer_open(const char* sheet_name, FxWriterHandle** out_handle);
FxStatus fx_writer_add_row(FxWriterHandle* handle, const FxCellValue* cells, uintptr_t len);
FxStatus fx_writer_finish_open_output(FxWriterHandle* handle, FxOutputHandle** out_output);
FxStatus fx_writer_finish_to_path(FxWriterHandle* handle, const char* path);
void fx_writer_close(FxWriterHandle* handle);

FxStatus fx_output_read_chunk(FxOutputHandle* handle, uint8_t* buffer, uintptr_t capacity, uintptr_t* out_len);
void fx_output_close(FxOutputHandle* handle);

const char* fx_error_message(const void* handle);

#ifdef __cplusplus
}
#endif

#endif
