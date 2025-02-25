//=============================================================================
// Module: sys_params.vh
//
// System wide localparam declarations
//
// Date         Who  What
//-----------------------------------------------------------------------------
// 23-Feb-2025  DWW  Initial Creation
//=============================================================================


`ifndef SYS_PARAMS_VH
`define SYS_PARAMS_VH

`include "../includes/sys_defines.vh"

// The base address of SMEM
localparam SMEM_BASE_ADDR = 32'h0010_0000;

// Base address of the SMEM buffer
localparam SBUF_BASE_ADDR = 32'h0018_0000;

// The host register that selects which banks to use for bank read/writes
localparam QSPI_BANK_EN_REG = 8'h28;

// The number of "banks" in the GenX chip. 
localparam GENX_BANK_COUNT = `GENX_BANK_COUNT;

// Various clock frequencies
localparam SYSCLK_FREQ    =  `SYSCLK_FREQ;
localparam GENX_QSPI_FREQ =  `GENX_QSPI_FREQ; 
localparam DAC_SPI_FREQ   =  `DAC_SPI_FREQ;


//=============================================================================
// These are the opcodes that the GenX QSPI receiver understands
//=============================================================================
localparam[7:0] GENX_QSPI_OPCODE_READ_SINGLE  = 8'hE8;
localparam[7:0] GENX_QSPI_OPCODE_WRITE_SINGLE = 8'hE9;
localparam[7:0] GENX_QSPI_OPCODE_READ_BURST   = 8'hEA;
localparam[7:0] GENX_QSPI_OPCODE_WRITE_BURST  = 8'hEB;
//=============================================================================

`endif


