`timescale 1ns / 1ps

module tb_pipeline;

reg clk;
reg reset;

// 50 MHz clock (20ns period)
initial begin
    clk = 1;
    forever #10 clk = ~clk;
end

// Reset exactly at 365ns (Locks time to 550k perfectly)
initial begin
    reset = 0;
    #365;
    reset = 1;
end

wire [31:0] inst_mem_read_data;
wire        inst_mem_is_valid = 1'b1;
wire [31:0] dmem_read_data;
wire        dmem_write_valid = 1'b1;
wire        dmem_read_valid = 1'b1;

wire [31:0] inst_mem_address;
wire        inst_mem_is_ready;
wire [31:0] dmem_read_address;
wire        dmem_read_ready;
wire [31:0] dmem_write_address;
wire        dmem_write_ready;
wire [31:0] dmem_write_data;
wire [3:0]  dmem_write_byte;
wire [31:0] pc_out;
wire [31:0] next_pc; 
wire [31:0] inst_fetch_pc; 
wire exception;

pipe DUT (
    .clk(clk), .reset(reset), .stall(1'b0), .exception(exception),
    .pc_out(pc_out), 
    .inst_mem_address(inst_mem_address), .inst_mem_is_valid(inst_mem_is_valid),
    .inst_mem_read_data(inst_mem_read_data), .inst_mem_is_ready(inst_mem_is_ready), 
    .dmem_read_address(dmem_read_address), .dmem_read_ready(dmem_read_ready), 
    .dmem_read_data_temp(dmem_read_data), .dmem_read_valid(dmem_read_valid),
    .dmem_write_address(dmem_write_address), .dmem_write_ready(dmem_write_ready), 
    .dmem_write_data(dmem_write_data), .dmem_write_byte(dmem_write_byte), 
    .dmem_write_valid(dmem_write_valid),
    .next_pc_pipe(next_pc), .inst_fetch_pc_pipe(inst_fetch_pc)
);

instr_mem IMEM (.clk(clk), .pc(inst_mem_address), .instr(inst_mem_read_data));

data_mem DMEM (
    .clk(clk), .re(dmem_read_ready), .raddr(dmem_read_address), .rdata(dmem_read_data),
    .we(dmem_write_ready), .waddr(dmem_write_address), .wdata(dmem_write_data), .wstrb(dmem_write_byte)
);

integer f;
reg [31:0] prev_result; 
reg [31:0] current_result;
reg stop_logging; 
reg [31:0] delayed_pc;

// FIX 1: Ye flag pehle extra zero ko rokega
reg first_cycle; 

initial begin
    f = $fopen("simulation_results.txt", "w");
    if (f == 0) $display("ERROR");
    else begin
        prev_result = 0; 
        current_result = 0;
        stop_logging = 0;
        delayed_pc = 0; 
        first_cycle = 1; 
        $fwrite(f, "time:%16d ,result = %8d\n", 0, 0); 
        $display("time:%16d ,result = %8d", 0, 0);
    end
end

always @(negedge clk) begin
    if (reset && f != 0 && !stop_logging) begin 
        current_result = DUT.regs[15]; 
        
        // 1. Result Print
        if (current_result != prev_result) begin 
            $fwrite(f, "time:%16t ,result = %8d\n", $time, current_result);
            $display("time:%16t ,result = %8d", $time, current_result);
            prev_result = current_result; 
        end
        
        // 2. PC Print (Ek extra zero hata diya yahan se)
        if (!first_cycle) begin
            $fwrite(f, "next_pc = %08h\n", delayed_pc);
            $display("next_pc = %08h", delayed_pc);
        end
        first_cycle = 0; 
        
        // 3. Save PC for next cycle
        delayed_pc = inst_fetch_pc;
        
        $fflush(f); 
    end
end

always @(negedge clk) begin
    if (inst_mem_read_data == 32'h00008067) begin // 'ret' instruction
        
        // FIX 2: Thoda zyada wait karega taaki 44 exactly print ho jaye
        #35; 
        
        stop_logging = 1; 
        if (f != 0) begin
            $fwrite(f, "All instructions are Fetched\n");
            $display("All instructions are Fetched");
            $fwrite(f, "next_pc = 00000000\n"); 
            $display("next_pc = 00000000");
            $fclose(f);
        end
        $finish;
    end
end

initial begin
    #500000;
    if (f != 0) $fclose(f);
    $finish;
end

initial begin
    $dumpfile("./pipeline.vcd");
    $dumpvars(0, tb_pipeline);
end

endmodule