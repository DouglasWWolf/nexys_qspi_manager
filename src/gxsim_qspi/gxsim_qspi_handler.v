//=============================================================================
// Module: gxsim_qspi_handler.v
//
// Handles read and write requests that were received from simulated QSPI
//
// Date         Who  What
//-----------------------------------------------------------------------------
// 23-Feb-2025  DWW  Initial Creation
//=============================================================================

// Uncomment this to add output ports for debugging on an ILA
`define ADD_DEBUG_PORTS

module gxsim_qspi_handler #
(
    parameter SMEM_BW = 512  // Number of bits in an SMEM "burst" read/write
)
(

    `ifdef ADD_DEBUG_PORTS
    output                   dbg_notify_write,
    output                   dbg_notify_read,  
    output     [        9:0] dbg_sck_counts,  
    output                   dbg_rw,      
    output     [       31:0] dbg_address,     
    output     [        1:0] dbg_cs_id,       
    output     [       31:0] dbg_wdata,       
    output     [SMEM_BW-1:0] dbg_rdata,       
    `endif

    input   clk, resetn,

    input      [        9:0] sck_counts,   // Count of the rising edges of SCK
    input                    rw,           // 1 == This is a write, 0 = This is a read
    input      [       31:0] address,      // Address that arrived on MOSI
    input      [        1:0] cs_id,        // Which chip-selects are active?   
    input      [       31:0] wdata,        // Data to be written to a register or SMEM
    output reg [SMEM_BW-1:0] rdata,        // Data read from registers or SMEM


    // Rising edge = cs_id, address, and rw signal have arrived
    input async_notify_read,   
                               
    // Rising edge = chip-select has de-asserted
    input async_notify_write   

);

// Bring in system-wide localparam definitions
`include "../includes/sys_params.vh"

genvar i;

// The number of 32-bit words that will fit into rdata
localparam SMEM_DW = SMEM_BW / 32;

// Definitions of the valid chip-select statess
localparam CS_HOST = 2'b10;
localparam CS_BANK = 2'b01;

// These are synchronous versions of the async input portss
wire notify_read, notify_write;

// This is data that's being read from the "host" register
wire[31:0] host_rdata;

// This is a bitmap of which banks are valid for read/writes
wire[GENX_BANK_COUNT-1:0] bank_select;

//=============================================================================
// Keep track of the prior state of the "notify signals" and use those states
// to perform edge detection
//=============================================================================
reg prior_notify_read, prior_notify_write;
//-----------------------------------------------------------------------------
always @(posedge clk) begin
    prior_notify_read  <= notify_read;
    prior_notify_write <= notify_write;
end
wire notify_read_rising  = (prior_notify_read  == 0) & (notify_read  == 1);
wire notify_write_rising = (prior_notify_write == 0) & (notify_write == 1);
//=============================================================================

//=============================================================================
// Sync async_notify_read into notify_read
//=============================================================================
xpm_cdc_single # (.SRC_INPUT_REG(0)) cdc_notify_read
(
    .src_in  (async_notify_read),   
    .dest_out(notify_read), 
    .dest_clk(clk), 
    .src_clk ()  
);
//=============================================================================


//=============================================================================
// Sync async_notify_write into notify_write
//=============================================================================
xpm_cdc_single # (.SRC_INPUT_REG(0)) cdc_notify_write
(
    .src_in  (async_notify_write),   
    .dest_out(notify_write), 
    .dest_clk(clk), 
    .src_clk ()  
);
//=============================================================================



//=============================================================================
// This block fills in port "rdata" with the requested data. 
//  
// Important inputs:
//      cs_id : is CS_HOST or CS_BANK active?)
//      rw    : 1 = This is a write, 0 = This is a read
//=============================================================================
always @(posedge clk) begin

    rdata <= 0;

    if (cs_id == CS_HOST && rw == 0)
        rdata <= {(host_rdata[31:0]), {SMEM_DW-1{32'b0}}};

end
//=============================================================================


// This will strobe high when it's time to write to a "host" register
wire write_host = notify_write_rising & (cs_id  == CS_HOST);




//=============================================================================
// This is a simulator for the GenX "host" registers
//=============================================================================
gxsim_host_reg host_registers
(
    .clk            (clk),
    .resetn         (resetn),
    .address        (address),
    .wdata          (wdata),
    .write_strobe   (write_host), 
    .rdata          (host_rdata),
    .bank_select    (bank_select)
);
//=============================================================================

   

//=============================================================================
// Banks containing bank registers, SMEM, and SBUF (SMEM buffer)
//=============================================================================
for (i=0; i<GENX_BANK_COUNT; i=i+1) begin

    gxsim_bank_reg_smem bank[i]
    (
        .clk            (clk),
        .resetn         (resetn),
        .address        (address),
        .wdata          (wdata),
        .rdata          (),
        .write_strobe   (),
        .bank_select    (bank_select[i])        
    );

end
//=============================================================================


//=============================================================================
// These ports make it very convenient to attach an ILA for debugging
//=============================================================================
`ifdef ADD_DEBUG_PORTS
assign dbg_notify_write = notify_write_rising;
assign dbg_notify_read  = notify_read_rising ;     
assign dbg_sck_counts   = sck_counts         ;             
assign dbg_rw           = rw                 ;
assign dbg_address      = address            ;              
assign dbg_cs_id        = cs_id              ;             
assign dbg_wdata        = wdata              ;                
assign dbg_rdata        = rdata              ;                 
`endif
//=============================================================================


endmodule