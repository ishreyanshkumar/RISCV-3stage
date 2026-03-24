`timescale 1ns/1ps

// ----------------------------------------------------------------------------
// Stage 2: Execute (EX)
// ALU operations, branch target calculation, and branch stall logic.
// Instantiates the EX -> WB pipeline register.
// ----------------------------------------------------------------------------
module execute
#(
	parameter [31:0] RESET = 32'h0000_0000
)
(
	input clk,
	input reset,

	// From ID/EX
	input  [31:0] reg_rdata1,     // RS1 data
	input  [31:0] reg_rdata2,     // RS2 data
	input  [31:0] execute_imm,    // Sign-extended immediate
	input  [31:0] pc,             // EX-stage PC
	input  [31:0] fetch_pc,       // Sequential fetch PC
	input     	immediate_sel,    // Select immediate vs RS2
	input     	mem_write,        // Store flag
	input     	jal,              // JAL flag
	input     	jalr,             // JALR flag
	input     	lui,              // LUI flag
	input     	alu,              // ALU op flag
	input     	branch,           // Branch flag
	input     	arithsubtype,     // SUB/SRA subtype
	input     	mem_to_reg,       // Load flag
	input     	stall_read,       // Stall propagation

	input  [4:0]  dest_reg_sel,   // RD index
	input  [2:0]  alu_op,         // ALU operation (func3)
	input  [1:0]  dmem_raddr,     // Memory read byte offset

	// From WB (branch tracking)
	input     	wb_branch_i,
	input     	wb_branch_nxt_i,

	// EX -> Pipeline
	output [31:0] alu_operand1,   // ALU input A
	output [31:0] alu_operand2,   // ALU input B
	output [31:0] write_address,  // Store address
	output    	branch_stall,     // Halt PC during branch

	output reg [31:0] next_pc,    // Computed next PC
	output reg    	branch_taken,   // Branch resolved true

	// EX -> WB
	output [31:0] wb_result,        // ALU result
	output    	wb_mem_write,       // Store commit flag
	output    	wb_alu_to_reg,      // ALU-to-register flag
	output [4:0]  wb_dest_reg_sel,  // WB destination register
	output    	wb_branch,          // Branch active flag
	output    	wb_branch_nxt,      // Branch overlap flag
	output    	wb_mem_to_reg,      // Load-to-register flag
	output [1:0]  wb_read_address,  // Memory alignment offset
	output [2:0]  mem_alu_operation // ALU op forwarded to WB
);

`include "opcode.vh"

// Internal signals
reg  [31:0] ex_result;       // ALU computation result
wire [32:0] ex_result_subs;  // Signed subtraction (for branches)
wire [32:0] ex_result_subu;  // Unsigned subtraction (for branches)

// ----------------------------------------------------------------------------
// Operand Selection
// ----------------------------------------------------------------------------

assign alu_operand1 = reg_rdata1;
assign alu_operand2 = immediate_sel ? execute_imm : reg_rdata2;

// ----------------------------------------------------------------------------
// Subtractions for Branch Comparisons
// ----------------------------------------------------------------------------

assign ex_result_subs =
	{alu_operand1[31], alu_operand1} -
	{alu_operand2[31], alu_operand2};

assign ex_result_subu = {1'b0, alu_operand1} - {1'b0, alu_operand2};

// ----------------------------------------------------------------------------
// Address & Branch Stall Logic
// ----------------------------------------------------------------------------

wire wb_branch_nxt_int;

assign write_address = alu_operand1 + execute_imm;
assign branch_stall  = wb_branch_nxt_i || wb_branch_i;

// ----------------------------------------------------------------------------
// Next PC Logic
// ----------------------------------------------------------------------------

always @(*) begin
	next_pc  	= fetch_pc + 4;
	branch_taken = !branch_stall;

	case (1'b1)
    	jal  : next_pc = pc + execute_imm;
    	jalr : next_pc = alu_operand1 + execute_imm;

    	branch: begin
        	case (alu_op)
            	BEQ:  begin
                	next_pc = (ex_result_subs == 0)
                          	? pc + execute_imm
                          	: fetch_pc + 4;
                	if (ex_result_subs != 0)
                    	branch_taken = 1'b0;
            	end
            	BNE:  begin
                	next_pc = (ex_result_subs != 0) 
						? pc + execute_imm 
						: fetch_pc + 4;
                	if(ex_result_subs == 0) 
                	   branch_taken = 1'b0;
            	end
            	BLT:  begin
                	next_pc = ex_result_subs[32]
                          	? pc + execute_imm
                          	: fetch_pc + 4;
                	if (!ex_result_subs[32])
                    	branch_taken = 1'b0;
            	end
            	BGE:  begin
                	next_pc = (!ex_result_subs[32]) 
						? pc+execute_imm 
						: fetch_pc + 4;
                	if(ex_result_subs[32])
                	    branch_taken = 1'b0;
            	end
            	BLTU: begin
                	next_pc = ex_result_subu[32]
                          	? pc + execute_imm
                          	: fetch_pc + 4;
                	if (!ex_result_subu[32])
                    	branch_taken = 1'b0;
            	end
            	BGEU: begin
                	next_pc = (!ex_result_subu[32]) ? pc+execute_imm : fetch_pc+4;
                	if(ex_result_subu[32])
                	    branch_taken = 1'b0;
            	end
            	default: next_pc = fetch_pc;
        	endcase
    	end

    	default: begin     	 
        	next_pc  	= fetch_pc + 4;
        	branch_taken = 1'b0;
    	end
	endcase
end

// ----------------------------------------------------------------------------
// ALU Result Logic
// ----------------------------------------------------------------------------

always @(*) begin
	case (1'b1)
    	mem_write: ex_result = alu_operand2;
    	jal,
    	jalr:  	ex_result = pc + 4;
    	lui:   	ex_result = execute_imm;

    	alu: begin
        	case (alu_op)
            	ADD : ex_result =
                  	arithsubtype
                  	? alu_operand1 - alu_operand2
                  	: alu_operand1 + alu_operand2;
            	SLL : ex_result = alu_operand1 << alu_operand2[4:0];
            	SLT : ex_result = ex_result_subs[32];
            	SLTU: ex_result = ex_result_subu[32];
            	XOR : ex_result = alu_operand1 ^ alu_operand2;
            	SR  : ex_result =
                  	arithsubtype
                  	? $signed(alu_operand1) >>> alu_operand2[4:0]
                  	: alu_operand1 >> alu_operand2[4:0]; 
            	OR  : ex_result = alu_operand1 | alu_operand2;
            	AND : ex_result = alu_operand1 & alu_operand2;
            	default: ex_result = 'hx;
        	endcase
    	end

    	default: ex_result = 'hx;
	endcase
end


// ----------------------------------------------------------------------------
// EX -> WB Pipeline Register
// ----------------------------------------------------------------------------

ex_mem_wb_reg u_ex_mem_wb (
	.clk        	(clk),                  // [IN]  from execute top
	.reset    	(reset),                    // [IN]  from execute top
	.stall_n    	(stall_read),           // [IN]  from pipe (stall propagation)

	.ex_result  	(ex_result),            // [IN]  from ALU result logic

	// Control inputs from EX combinational
	.mem_write  	(mem_write && !branch_stall), // [IN]  from EX (gated store)
	.alu_to_reg 	(alu | lui | jal |      // [IN]  from EX (any reg-write instr)
                  	jalr | mem_to_reg),
	.dest_reg_sel   (dest_reg_sel),         // [IN]  from IF_ID (RD index)
	.branch_taken   (branch_taken),         // [IN]  from EX branch resolution
	.mem_to_reg 	(mem_to_reg),           // [IN]  from IF_ID (load flag)
	.read_address   (dmem_raddr),           // [IN]  from pipe (byte offset)
	.alu_operation  (alu_op),               // [IN]  from IF_ID (func3)

	// Registered outputs to WB stage
	.ex_mem_result    	(wb_result),        // [OUT] to pipe IF_ID, reg WB
	.ex_mem_mem_write 	(wb_mem_write),     // [OUT] to pipe dmem_write_ready
	.ex_mem_alu_to_reg	(wb_alu_to_reg),    // [OUT] to pipe IF_ID, reg WB
	.ex_mem_dest_reg_sel  (wb_dest_reg_sel),// [OUT] to pipe IF_ID, reg WB
	.ex_mem_branch    	(wb_branch),        // [OUT] to pipe wb_stage, EX loopback
	.ex_mem_branch_nxt	(wb_branch_nxt),    // [OUT] to EX loopback
	.ex_mem_mem_to_reg	(wb_mem_to_reg),    // [OUT] to pipe IF_ID, wb_stage, reg WB
	.ex_mem_read_address  (wb_read_address),// [OUT] to pipe wb_stage
	.ex_mem_alu_operation (mem_alu_operation)// [OUT] to pipe wb_stage
);

endmodule


module ex_mem_wb_reg (
	input     	clk,
	input     	reset,
	input     	stall_n,

	input  [31:0] ex_result,

	// Control from EX
	input     	mem_write,
	input     	alu_to_reg,
	input  [4:0]  dest_reg_sel,
	input     	branch_taken,
	input     	mem_to_reg,
	input  [1:0]  read_address,
	input  [2:0]  alu_operation,

	// Registered outputs to WB
	output reg [31:0] ex_mem_result,
	output reg    	ex_mem_mem_write,
	output reg    	ex_mem_alu_to_reg,
	output reg [4:0]  ex_mem_dest_reg_sel,
	output reg    	ex_mem_branch,
	output reg    	ex_mem_branch_nxt,
	output reg    	ex_mem_mem_to_reg,
	output reg [1:0]  ex_mem_read_address,
	output reg [2:0]  ex_mem_alu_operation
);

// EX/MEM -> WB Pipeline Register
always @(posedge clk or posedge reset) begin
	if (reset) begin
    	ex_mem_result     	<= 32'h0;
    	ex_mem_mem_write  	<= 1'b0;
    	ex_mem_alu_to_reg 	<= 1'b0;
    	ex_mem_dest_reg_sel   <= 5'h0;
    	ex_mem_branch     	<= 1'b0;
    	ex_mem_branch_nxt 	<= 1'b0;
    	ex_mem_mem_to_reg 	<= 1'b0;
    	ex_mem_read_address   <= 2'h0;
    	ex_mem_alu_operation  <= 3'h0;
	end
	else if (!stall_n) begin
    	ex_mem_result     	<= ex_result;
    	ex_mem_mem_write  	<= mem_write;
    	ex_mem_alu_to_reg 	<= alu_to_reg;
    	ex_mem_dest_reg_sel   <= dest_reg_sel;
    	ex_mem_branch     	<= branch_taken;
    	ex_mem_branch_nxt 	<= ex_mem_branch;   
    	ex_mem_mem_to_reg 	<= mem_to_reg;
    	ex_mem_read_address   <= read_address;
    	ex_mem_alu_operation  <= alu_operation;
	end
end

endmodule
