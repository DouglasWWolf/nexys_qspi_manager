//Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Command: generate_target bd_5b7c_wrapper.bd
//Design : bd_5b7c_wrapper
//Purpose: IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module bd_5b7c_wrapper
   (clk,
    probe0,
    probe1);
  input clk;
  input [99:0]probe0;
  input [64:0]probe1;

  wire clk;
  wire [99:0]probe0;
  wire [64:0]probe1;

  bd_5b7c bd_5b7c_i
       (.clk(clk),
        .probe0(probe0),
        .probe1(probe1));
endmodule
