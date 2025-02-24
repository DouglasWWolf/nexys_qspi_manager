

module genx_qspi_handler # (DW = 256)
(
    input   clk, resetn,

    // These go high for one cycle to serve as ILA triggers
    output       dbg_notify_write,
    output       dbg_notify_read,  

    input [ 9:0] sck_counts,         // Count of the rising edges of SCK
    input [ 7:0] opcode,             // Opcode that arrived on MOSI
    input [31:0] address,            // Address that arrived on MOSI
    input [ 1:0] chip_select,        // Which chip-selects are active?

    input        async_notify_read,  // Rising edge = chip_select, address, and opcode
                                     // have arrived

    input        async_notify_write  // Chip-select has de-asserted
);

// These are synchronous versions of the async input ports
wire notify_read, notify_write;

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
// Assign output ports for debugging via ILA
//=============================================================================
assign dbg_notify_write = notify_write_rising;
assign dbg_notify_read  = notify_read_rising;
//=============================================================================


endmodule