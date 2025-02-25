//=============================================================================
// Module: sys_defines.vh
//
// System wide `define declarations
//
// Date         Who  What
//-----------------------------------------------------------------------------
// 23-Feb-2025  DWW  Initial Creation
//=============================================================================


`ifndef SYS_DEFINES_VH
`define SYS_DEFINES_VH

//================================================
// Only one of these should be defined at a time
//================================================
`define GXSIM_NEXYS_A7
//`define GXSIM_XUPPL4
//`define GXSIM_OFF_BOARD
//`define GXSIM_REAL
//================================================

`ifdef GXSIM_NEXYS_A7
    `define SYSCLK_FREQ     50000000
    `define GENX_QSPI_FREQ  10000000
    `define DAC_SPI_FREQ    10000000
`endif



`define GENX_BANK_COUNT  10

`endif


