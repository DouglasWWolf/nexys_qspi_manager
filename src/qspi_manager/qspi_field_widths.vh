// Code gaurd to prevent multiple `include
`ifndef QSPI_FIELD_WIDTHS_VH
`define QSPI_FIELD_WIDTHS_VH 

// This should be the sum of the lengths below
`define QSPI_REQ_WIDTH  100

// These are the lengths of the individual fields in a QSPI reqest
`define QSPI_CMD_LEN      3
`define QSPI_ADDR_LEN    32
`define QSPI_WDATA_LEN   64
`define QSPI_START_LEN    1

// This should be the sum of the lengths below
`define QSPI_RSP_WIDTH   65

// These are the lengths of the individual fields in a QSPI response
`define QSPI_RDATA_LEN   64
`define QSPI_IDLE_LEN     1

// End of code gaurd
`endif
