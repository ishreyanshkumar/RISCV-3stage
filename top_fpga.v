`timescale 1ns / 1ps

module top_fpga #(
    parameter IMEMSIZE = 4096,
    parameter DMEMSIZE = 4096
)(
    input  wire clk,
    input  wire reset,
    output [15:0] led
);

wire exception;

// Clock divider (50 MHz -> ~1 Hz)
reg [25:0] clk_cnt;
reg        slow_clk;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        clk_cnt  <= 26'd0;
        slow_clk <= 1'b0;
    end else begin
        if (clk_cnt == 26'd49_999_999) begin
            clk_cnt  <= 26'd0;
            slow_clk <= ~slow_clk;
        end else begin
            clk_cnt <= clk_cnt + 1'b1;
        end
    end
end

// Reset synchronizer
reg reset_sync;
always @(posedge slow_clk or posedge reset) begin
    if (reset)
        reset_sync <= 1'b1;    // Assert on button press (active-high)
    else
        reset_sync <= 1'b0;    // Deassert on slow_clk edge
end

// Pipeline <-> Memory interconnect
wire [31:0] inst_mem_read_data;     // IMEM -> pipe: fetched instruction
wire        inst_mem_is_valid;      // Always 1: ROM always ready
wire [31:0] dmem_read_data;         // DMEM -> pipe: loaded data word
wire        dmem_write_valid;       // Always 1: write completes in 1 cycle
wire        dmem_read_valid;        // Always 1: read completes in 1 cycle
wire [31:0] pc_out_wire;            // pipe -> LEDs: current PC for debug
wire [31:0] inst_mem_address;       // pipe -> IMEM: fetch PC address
wire        dmem_read_ready;        // pipe -> DMEM: read enable
wire [31:0] dmem_read_address;      // pipe -> DMEM: load address
wire        dmem_write_ready;       // pipe -> DMEM: write enable
wire [31:0] dmem_write_address;     // pipe -> DMEM: store address
wire [31:0] dmem_write_data;        // pipe -> DMEM: store payload
wire [ 3:0] dmem_write_byte;        // pipe -> DMEM: byte-enable strobes

assign inst_mem_is_valid = 1'b1;
assign dmem_write_valid  = 1'b1;
assign dmem_read_valid   = 1'b1;
assign led               = exception ? 16'hFFFF : pc_out_wire[15:0];

// Pipeline CPU
pipe pipe_u (
    .clk                    (slow_clk),         // [IN]  from clock divider
    .reset                  (reset_sync),       // [IN]  from reset synchronizer
    .stall                  (1'b0),             // [IN]  tied low (no stall)
    .exception              (exception),        // [OUT] to LED logic
    .inst_mem_is_valid      (inst_mem_is_valid), // [IN]  from tie-off (always 1)
    .inst_mem_read_data     (inst_mem_read_data),// [IN]  from IMEM
    .dmem_read_data_temp    (dmem_read_data),   // [IN]  from DMEM
    .dmem_write_valid       (dmem_write_valid), // [IN]  from tie-off (always 1)
    .dmem_read_valid        (dmem_read_valid),  // [IN]  from tie-off (always 1)
    .pc_out                 (pc_out_wire),      // [OUT] to LED logic
    .inst_mem_address_out   (inst_mem_address), // [OUT] to IMEM
    .dmem_read_ready_out    (dmem_read_ready),  // [OUT] to DMEM
    .dmem_read_address_out  (dmem_read_address),// [OUT] to DMEM
    .dmem_write_ready_out   (dmem_write_ready), // [OUT] to DMEM
    .dmem_write_address_out (dmem_write_address),// [OUT] to DMEM
    .dmem_write_data_out    (dmem_write_data),  // [OUT] to DMEM
    .dmem_write_byte_out    (dmem_write_byte)   // [OUT] to DMEM
);

// Instruction Memory
instr_mem IMEM (
    .clk   (clk),                               // [IN]  from FPGA clock
    .pc    (inst_mem_address),                   // [IN]  from pipe
    .instr (inst_mem_read_data)                  // [OUT] to pipe
);

// Data Memory
data_mem DMEM (
    .clk   (clk),                                // [IN]  from FPGA clock
    .re    (dmem_read_ready),                    // [IN]  from pipe
    .raddr (dmem_read_address),                  // [IN]  from pipe
    .rdata (dmem_read_data),                     // [OUT] to pipe
    .we    (dmem_write_ready),                   // [IN]  from pipe
    .waddr (dmem_write_address),                 // [IN]  from pipe
    .wdata (dmem_write_data),                    // [IN]  from pipe
    .wstrb (dmem_write_byte)                     // [IN]  from pipe
);

endmodule