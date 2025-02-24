`ifndef GENX_QSPI_OPCODES_VH
`define GENX_QSPI_OPCODES_VH

//=============================================================================
// These are the opcodes that the GenX QSPI receiver understands
//=============================================================================
localparam[7:0] GENX_QSPI_OPCODE_READ_SINGLE  = 8'hE8;
localparam[7:0] GENX_QSPI_OPCODE_WRITE_SINGLE = 8'hE9;
localparam[7:0] GENX_QSPI_OPCODE_READ_BURST   = 8'hEA;
localparam[7:0] GENX_QSPI_OPCODE_WRITE_BURST  = 8'hEB;
//=============================================================================

`endif


