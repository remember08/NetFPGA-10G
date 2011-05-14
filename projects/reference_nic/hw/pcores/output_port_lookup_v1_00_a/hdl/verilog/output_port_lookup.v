////////////////////////////////////////////////////////////////////////
//
//  NetFPGA-10G http://www.netfpga.org
//
//  Module:
//          output_port_lookup
//
//  Description:
//          Hardwire the hardware interfaces to CPU and vice versa
//                 
//  Revision history:
//          2011/5/13 gac1: Initial check-in
//
////////////////////////////////////////////////////////////////////////
module output_port_lookup
  #(
    //Master AXI Stream Data Width
    parameter C_AXIS_DATA_WIDTH=256,
    parameter C_USER_WIDTH=128
    )
   (
    // Global Ports
    input axi_aclk;
    input axi_resetn;

    // Master Stream Ports (interface to data path)
    output reg [C_AXIS_DATA_WIDTH - 1:0] m_axis_tdata,
    output reg [((C_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_tstrb,
    output reg [C_USER_WIDTH-1:0] m_axis_tuser,
    output reg m_axis_tvalid,
    input  m_axis_tready,
    output reg m_axis_tlast,

    // Slave Stream Ports (interface to RX queues)
    input [C_AXIS_DATA_WIDTH - 1:0] s_axis_tdata,
    input [((C_AXIS_DATA_WIDTH / 8)) - 1:0] s_axis_tstrb,
    input [C_USER_WIDTH-1:0] s_axis_tuser,
    input  s_axis_tvalid,
    output s_axis_tready,
    input  s_axis_tlast
    );

   function integer log2;
      input integer number;
      begin
         log2=0;
         while(2**log2<number) begin
            log2=log2+1;
         end
      end
   endfunction // log2

   // ------------ Internal Params --------
   localparam MODULE_HEADER = 0;
   localparam IN_PACKET     = 1;

   //------------- Wires ------------------
   reg [C_USER_WIDTH-1:0] in_tuser_modded;
   reg [7:0] 		  decoded_src;
   reg 			  state, state_next;     
   
   // ------------ Modules ----------------
   
   small_fifo
        #( .WIDTH(C_AXIS_DATA_WIDTH+C_USER_WIDTH+C_AXIS_DATA_WIDTH/8+1),
           .MAX_DEPTH_BITS(2))
      input_fifo
        (// Outputs
         .dout                           ({m_axis_tlast, m_axis_tuser, m_axis_tstrb, m_axis_tdata}),
         .full                           (),
         .nearly_full                    (in_fifo_nearly_full),
         .prog_full                      (),
         .empty                          (in_fifo_empty),
         // Inputs
         .din                            ({s_axis_tlast, in_tuser_modded, s_axis_tstrb, s_axis_tdata}),
         .wr_en                          (in_tvalid & ~nearly_full),
         .rd_en                          (in_fifo_rd_en),
         .reset                          (~axi_resetn),
         .clk                            (axi_aclk));
   
   // ------------- Logic ----------------

   assign s_axis_tready = !in_fifo_nearly_full;

   // packet is from the cpu if it is on an odd numbered port
   assign pkt_is_from_cpu = s_axis_tuser[`SRC_PORT_POS+8:`SRC_PORT_POS];

   // decode the source port
   always @(*) begin
      decoded_src = 0;
      decoded_src[s_axis_tuser[`SRC_PORT_POS+8:`SRC_PORT_POS]] = 1'b1;
   end
     
   // modify the dst port in tuser
   always @(*) begin
      in_tuser_modded = s_axis_tuser;
      state_next      = state;

      case(state)
	MODULE_HEADER: begin
	   if (s_axis_tvalid) begin
	      if(pkt_is_from_cpu) begin
		 in_tuser_modded[`DST_PORT_POS+8:`DST_PORT_POS] = {1'b0, decoded_src[7:1]};
	      end
	      else begin
		 in_tuser_modded[`DST_PORT_POS+8:`DST_PORT_POS] = {decoded_src[6:0], 1'b0};
	      end
	   end
	   state_next = IN_PACKET;
	end // case: MODULE_HEADER

	IN_PACKET: begin
	   if(s_axis_tlast) begin
	      state_next = MODULE_HEADER;
	   end
	end
      endcase // case (state)      
   end // always @ (*)

   always @(posedge clk) begin
      if(axi_resetn) begin
	 state <= MODULE_HEADER;
      end
      else begin
	 state <= state_next;
      end
   end

   // Handle output
   assign in_fifo_rd_en = m_axis_tready && !in_fifo_empty;
   always @(posedge clk) begin
      m_axis_tvalid <= ~axi_resetn ? 0 : in_fifo_rd_en;
   end

endmodule // output_port_lookup

   
		
   
