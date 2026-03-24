`timescale 1ns / 1ps

module tb_pipeline;

reg clk;
reg reset;

// 50 MHz clock (20ns period)
initial begin
    clk = 1;
    forever #10 clk = ~clk;
end

// Reset release at 365ns
initial begin
    reset = 1;
    #365;
    reset = 0;
end

wire [31:0] inst_mem_read_data;             // IMEM -> pipe: fetched instruction
wire        inst_mem_is_valid = 1'b1;       // Always valid (ROM assumed ready)
wire [31:0] dmem_read_data;                 // DMEM -> pipe: loaded data word
wire        dmem_write_valid = 1'b1;        // Always valid (1-cycle write)
wire        dmem_read_valid = 1'b1;         // Always valid (1-cycle read)

wire [31:0] inst_mem_address;               // pipe -> IMEM: fetch PC address
wire        inst_mem_is_ready;              // pipe: ready for next instruction
wire [31:0] dmem_read_address;              // pipe -> DMEM: load address
wire        dmem_read_ready;                // pipe -> DMEM: read enable
wire [31:0] dmem_write_address;             // pipe -> DMEM: store address
wire        dmem_write_ready;               // pipe -> DMEM: write enable
wire [31:0] dmem_write_data;                // pipe -> DMEM: store payload
wire [3:0]  dmem_write_byte;                // pipe -> DMEM: byte-enable strobes
wire [31:0] pc_out;                         // pipe: current PC
wire [31:0] next_pc;                        // pipe: computed next PC
wire [31:0] inst_fetch_pc;                  // pipe: instruction fetch sequence PC
wire exception;                             // pipe: illegal instr / misaligned fetch

pipe DUT (
    .clk(clk), .reset(reset), .stall(1'b0),         // [IN]  from TB
    .exception(exception),                            // [OUT] to TB
    .pc_out(pc_out),                                  // [OUT] to TB
    .inst_mem_address(inst_mem_address),               // [OUT] to IMEM
    .inst_mem_is_valid(inst_mem_is_valid),             // [IN]  from TB (tied 1)
    .inst_mem_read_data(inst_mem_read_data),           // [IN]  from IMEM
    .inst_mem_is_ready(inst_mem_is_ready),             // [OUT] to TB
    .dmem_read_address(dmem_read_address),             // [OUT] to DMEM
    .dmem_read_ready(dmem_read_ready),                 // [OUT] to DMEM
    .dmem_read_data_temp(dmem_read_data),              // [IN]  from DMEM
    .dmem_read_valid(dmem_read_valid),                 // [IN]  from TB (tied 1)
    .dmem_write_address(dmem_write_address),           // [OUT] to DMEM
    .dmem_write_ready(dmem_write_ready),               // [OUT] to DMEM
    .dmem_write_data(dmem_write_data),                 // [OUT] to DMEM
    .dmem_write_byte(dmem_write_byte),                 // [OUT] to DMEM
    .dmem_write_valid(dmem_write_valid),               // [IN]  from TB (tied 1)
    .next_pc_pipe(next_pc),                            // [OUT] to TB logging
    .inst_fetch_pc_pipe(inst_fetch_pc)                 // [OUT] to TB logging
);

instr_mem IMEM (
    .clk(clk),                                        // [IN]  from TB
    .pc(inst_mem_address),                             // [IN]  from pipe
    .instr(inst_mem_read_data)                         // [OUT] to pipe
);

data_mem DMEM (
    .clk(clk),                                        // [IN]  from TB
    .re(dmem_read_ready),   .raddr(dmem_read_address), // [IN]  from pipe
    .rdata(dmem_read_data),                            // [OUT] to pipe
    .we(dmem_write_ready),  .waddr(dmem_write_address), // [IN]  from pipe
    .wdata(dmem_write_data), .wstrb(dmem_write_byte)   // [IN]  from pipe
);

integer f;
reg [31:0] prev_result; 
reg [31:0] current_result;
reg stop_logging; 
reg [31:0] delayed_pc;
reg first_cycle;                            // Skips first-cycle zero in PC log

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
    if (!reset && f != 0 && !stop_logging) begin
        current_result = DUT.regs[15]; 
        
        // Log result changes
        if (current_result != prev_result) begin 
            $fwrite(f, "time:%16t ,result = %8d\n", $time, current_result);
            $display("time:%16t ,result = %8d", $time, current_result);
            prev_result = current_result; 
        end
        
        // Log PC (skip first cycle to avoid extra zero)
        if (!first_cycle) begin
            $fwrite(f, "next_pc = %08h\n", delayed_pc);
            $display("next_pc = %08h", delayed_pc);
        end
        first_cycle = 0; 
        
        delayed_pc = inst_fetch_pc;
        
        $fflush(f); 
    end
end

always @(negedge clk) begin
    if (inst_mem_read_data == 32'h00008067) begin // 'ret' instruction
        #35; // Wait for final result to propagate
        
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