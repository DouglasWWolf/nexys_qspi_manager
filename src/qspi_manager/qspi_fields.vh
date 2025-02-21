// Code gaurds to prevent multiple `include
`ifndef QSPI_FIELDS_VH
`define QSPI_FIELDS_VH

`include "qspi_field_widths.vh" 

// Define the widths of the QSPI request fields
localparam QSPI_CMD_LEN     = `QSPI_CMD_LEN    ;
localparam QSPI_BANKMAP_LEN = `QSPI_BANKMAP_LEN;
localparam QSPI_ADDR_LEN    = `QSPI_ADDR_LEN   ;
localparam QSPI_WDATA_LEN   = `QSPI_WDATA_LEN  ;
localparam QSPI_START_LEN   = `QSPI_START_LEN  ;

localparam QSPI_RDATA_LEN   = `QSPI_RDATA_LEN  ;
localparam QSPI_IDLE_LEN    = `QSPI_IDLE_LEN   ;

/*
****************************************************************************
  This block of code checks to see if `QSPI_REQ_WIDTH and `QSPI_RSP_WIDTH 
  computed correctly in file "qspi_field_widths.vh"

  If this gets to be a hassle to maintain, this entire block can be deleted
  and the only side-effect will be that RTL engineers had better be able to
  add well enough to specify the correct values for `QSPI_REQ_WIDTH and
  `QSPI_RSP_WIDTH
****************************************************************************
 */
// Compute the total width the QSPI request fields
localparam COMPUTED_REQ_WIDTH = QSPI_CMD_LEN
                              + QSPI_BANKMAP_LEN
                              + QSPI_ADDR_LEN
                              + QSPI_WDATA_LEN 
                              + QSPI_START_LEN;

// Compute the total width the QSPI reponse fields
localparam COMPUTED_RSP_WIDTH = QSPI_RDATA_LEN
                              + QSPI_IDLE_LEN;

// Generate a "field too big" error if the computed width doesn't match `QSPI_REQ_WIDTH
localparam QSPI_REQ_ERROR = (COMPUTED_REQ_WIDTH == `QSPI_REQ_WIDTH) ? 0 : 999999999;
wire[QSPI_REQ_ERROR:0] qspi_req_dummy;


// Generate a "field too big" error if the computed width doesn't match `QSPI_RSP_WIDTH
localparam QSPI_RSP_ERROR = (COMPUTED_RSP_WIDTH == `QSPI_RSP_WIDTH) ? 0 : 999999999;
wire[QSPI_RSP_ERROR:0] qspi_rsp_dummy;

/*
****************************************************************************
****************************************************************************
 */

//=============================================================================
// Here we declare the broken out fields for interacting with QSPI
//=============================================================================
`ifdef QSPI_FRONT_END
    wire[    `QSPI_CMD_LEN-1:0] qspi_cmd;  
    wire[`QSPI_BANKMAP_LEN-1:0] qspi_bankmap;
    wire[   `QSPI_ADDR_LEN-1:0] qspi_addr; 
    wire[  `QSPI_WDATA_LEN-1:0] qspi_wdata;
    wire[  `QSPI_START_LEN-1:0] qspi_start;
    reg [  `QSPI_RDATA_LEN-1:0] qspi_rdata; 
    reg [   `QSPI_IDLE_LEN-1:0] qspi_idle;
`else
    reg [    `QSPI_CMD_LEN-1:0] qspi_cmd;  
    reg [`QSPI_BANKMAP_LEN-1:0] qspi_bankmap;
    reg [   `QSPI_ADDR_LEN-1:0] qspi_addr; 
    reg [  `QSPI_WDATA_LEN-1:0] qspi_wdata;
    reg [  `QSPI_START_LEN-1:0] qspi_start;
    wire[  `QSPI_RDATA_LEN-1:0] qspi_rdata;
    wire[   `QSPI_IDLE_LEN-1:0] qspi_idle;
`endif
//=============================================================================


`define QSPI_REQ_FIELDS {qspi_cmd, qspi_bankmap, qspi_addr, qspi_wdata, qspi_start}
`define QSPI_RSP_FIELDS {qspi_idle, qspi_rdata}

// Commands that can be placed in the "qspi_cmd" field
localparam QSPI_CMD_WHR  = 0;  // Write host register
localparam QSPI_CMD_WBR  = 1;  // Write bank register
localparam QSPI_CMD_RHR  = 2;  // Read host register
localparam QSPI_CMD_RBR  = 3;  // Read bank register
localparam QSPI_CMD_RMEM = 4;  // Read SMEM  (64-bit read)
localparam QSPI_CMD_WMEM = 5;  // Write SMEM (64-bit write)

// End of code gaurd
`endif
