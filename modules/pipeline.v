// ----------------------------------------------------------------------------
// Pipeline Module
// Top-level pipeline connecting IF/ID, EX, WB stages, register file, and PC.
// ----------------------------------------------------------------------------
`include "IF_ID.v"
`include "execute.v"
`include "memory.v"
`include "wb.v"

 module pipe
#(
	parameter [31:0]            RESET = 32'h0000_0000
)
(
	input                   clk,
	input                   reset,
	input                   stall,
	output                  exception,  
	output [31:0] pc_out,

	// Instruction memory interface
	output      [31: 0] inst_mem_address,
	input                   inst_mem_is_valid,
	input       [31: 0] inst_mem_read_data,
	output                  inst_mem_is_ready,

	// Data memory interface
	output      [31: 0] dmem_read_address,
	output                  dmem_read_ready,
	input       [31: 0] dmem_read_data_temp,
	input                   dmem_read_valid,
	output      [31: 0] dmem_write_address,
	output                  dmem_write_ready,
	output      [31: 0] dmem_write_data,
	output      [ 3: 0] dmem_write_byte,
	input                   dmem_write_valid,
	output [31: 0] next_pc_pipe,
	output [31: 0] inst_fetch_pc_pipe
);
    
	// ----------------------------------------------------------------------------
	// Internal Wires and Registers
	// ----------------------------------------------------------------------------

	// --- Data Memory Wires ---
	wire      [31: 0] dmem_read_data;           // From dmem_read_data_temp -> wb_stage
	wire        [1:0] dmem_read_offset;         // PC[1:0] from dmem_read_address -> execute
	wire              dmem_read_valid_checker;   // From dmem_read_valid (tracking signal)
    
	// --- IF/ID Stage Wires ---
	reg       [31: 0] immediate;                // Local unused reg (IF_ID handles immediates)
	wire              immediate_sel;            // IF_ID -> execute: select immediate vs RS2
	wire      [ 4: 0] src1_select;              // IF_ID -> reg file: RS1 index
	wire      [ 4: 0] src2_select;              // IF_ID -> reg file: RS2 index
	wire      [ 4: 0] dest_reg_sel;             // IF_ID -> execute: RD index
	wire      [ 2: 0] alu_operation;            // IF_ID -> execute, wb_stage: func3 ALU op
	wire              arithsubtype;             // IF_ID -> execute: ADD vs SUB (bit 30)
	wire              mem_write;                // IF_ID -> execute, wb_stage: store flag
	wire              mem_to_reg;               // IF_ID -> execute, dmem_read_ready: load flag
	wire              illegal_inst;             // IF_ID internal: invalid opcode flag
	wire      [31: 0] execute_immediate;        // IF_ID -> execute, dmem_read_address: sign-extended imm
	wire              alu;                      // IF_ID -> execute: ALU instruction flag
	wire              lui;                      // IF_ID -> execute: LUI flag
	wire              jal;                      // IF_ID -> execute: JAL flag
	wire              jalr;                     // IF_ID -> execute: JALR flag
	wire              branch;                   // IF_ID -> execute: branch flag
	reg               stall_read;               // Local -> IF_ID, wb, execute, PC logic: 1-cycle stall
	wire      [31: 0] instruction;              // IF_ID <-> pipe: decoded instruction feedback loop
	wire      [31: 0] reg_rdata2;               // Reg file -> execute: RS2 read data
	wire      [31: 0] reg_rdata1;               // Reg file -> execute: RS1 read data
	reg       [31: 0] regs [31: 1];             // 31-entry register file (x1–x31)

	// --- PC Logic Wires ---
	wire        [31: 0] pc;                     // IF_ID -> execute: EX-stage PC
	wire        [31: 0] inst_fetch_pc;          // wb_stage -> IF_ID, inst_fetch_pc_pipe: fetch PC
	reg         [31: 0] fetch_pc;               // Local -> execute, wb_stage, pc_out: current PC

	// --- Stall Wires ---
	wire 	wb_stall_first;                     // wb_stage: branch stall cycle 1
	wire 	wb_stall_second;                    // wb_stage: branch stall cycle 2
	wire	wb_stall;                           // wb_stage -> IF_ID, reg forwarding: merged stall

	// --- Execute Stage Wires ---
	wire        [31: 0] next_pc;                // execute -> fetch_pc, next_pc_pipe: computed next PC
	wire        [31: 0] write_address;          // execute -> wb_stage: store target address
	wire                 branch_taken;          // execute: branch resolution result
	wire                 branch_stall;          // execute -> PC logic: inhibit PC advance
	wire        [31:0] alu_operand1;            // execute -> dmem_read_address, wb_stage: ALU op1
	wire        [31:0] alu_operand2;            // execute -> wb_stage: ALU op2

	// --- Write-Back Wires ---
	wire                 wb_alu_to_reg;         // execute -> IF_ID, reg WB: ALU result to register
	wire        [31: 0] wb_result;              // execute -> IF_ID, reg WB: ALU output value
	wire        [ 2: 0] wb_alu_operation;       // execute -> wb_stage: ALU op forwarded to WB
	wire                 wb_mem_write;          // execute -> dmem_write_ready: store commit flag
	wire                 wb_mem_to_reg;         // execute -> IF_ID, wb, reg WB: load-to-register flag
	wire        [ 4: 0] wb_dest_reg_sel;        // execute -> IF_ID, reg WB: destination register index
	wire                 wb_branch;             // execute <-> wb_stage: branch active flag
	wire                 wb_branch_nxt;         // execute <-> wb_stage: branch overlap flag
	wire        [31: 0] wb_write_address;       // wb_stage -> dmem_write_address: committed store addr
	wire        [ 1: 0] wb_read_address;        // execute -> wb_stage: byte/half alignment offset
	wire        [ 3: 0] wb_write_byte;          // wb_stage -> dmem_write_byte: byte write strobes
	wire        [31: 0] wb_write_data;          // wb_stage -> dmem_write_data: store payload
	wire        [31: 0] wb_read_data;           // wb_stage -> IF_ID, reg WB: sign-extended load data

// ----------------------------------------------------------------------------
// Memory Address/Data Assignments
// ----------------------------------------------------------------------------
assign dmem_write_address       = wb_write_address;
assign dmem_read_address        = alu_operand1 + execute_immediate;
assign dmem_read_offset = dmem_read_address[1:0];
assign dmem_read_ready          = mem_to_reg;
assign dmem_write_ready         = wb_mem_write;
assign dmem_write_data          = wb_write_data;
assign dmem_write_byte          = wb_write_byte;
assign dmem_read_data           = dmem_read_data_temp;
assign dmem_read_valid_checker  = dmem_read_valid;

// ----------------------------------------------------------------------------
// Instruction Fetch / Decode
// ----------------------------------------------------------------------------
IF_ID IF_ID_stage (
	.clk            (clk),                  // [IN]  from pipe top
	.reset          (reset),                // [IN]  from pipe top
	.stall          (stall),                // [IN]  from pipe top
	.exception      (exception),            // [OUT] to pipe top

	.inst_mem_is_valid  (inst_mem_is_valid), // [IN]  from pipe top (ext memory)
	.inst_mem_read_data (inst_mem_read_data),// [IN]  from pipe top (ext memory)

	.stall_read_i   (stall_read),           // [IN]  from pipe stall_read reg
	.inst_fetch_pc  (inst_fetch_pc),        // [IN]  from wb_stage
	.instruction_i  (instruction),          // [IN]  from IF_ID instruction_o (feedback)

	.wb_stall       (wb_stall),             // [IN]  from wb_stage
	.wb_alu_to_reg  (wb_alu_to_reg),        // [IN]  from execute (EX->WB reg)
	.wb_mem_to_reg  (wb_mem_to_reg),        // [IN]  from execute (EX->WB reg)
	.wb_dest_reg_sel(wb_dest_reg_sel),      // [IN]  from execute (EX->WB reg)
	.wb_result      (wb_result),            // [IN]  from execute (EX->WB reg)
	.wb_read_data   (wb_read_data),         // [IN]  from wb_stage

	.inst_mem_offset(inst_mem_address[1:0]),// [IN]  from wb_stage (PC[1:0])

	.execute_immediate_w (execute_immediate),// [OUT] to execute, dmem_read_addr
	.immediate_sel_w	(immediate_sel),    // [OUT] to execute
	.alu_w          (alu),                  // [OUT] to execute
	.lui_w          (lui),                  // [OUT] to execute
	.jal_w          (jal),                  // [OUT] to execute
	.jalr_w         (jalr),                // [OUT] to execute
	.branch_w       (branch),               // [OUT] to execute
	.mem_write_w    (mem_write),            // [OUT] to execute, wb_stage
	.mem_to_reg_w   (mem_to_reg),           // [OUT] to execute, dmem_read_ready
	.arithsubtype_w 	(arithsubtype),     // [OUT] to execute
	.pc_w           (pc),                   // [OUT] to execute
	.src1_select_w  (src1_select),          // [OUT] to reg file read
	.src2_select_w  (src2_select),          // [OUT] to reg file read
	.dest_reg_sel_w 	(dest_reg_sel),     // [OUT] to execute
	.alu_operation_w	(alu_operation),    // [OUT] to execute, wb_stage
	.illegal_inst_w 	(illegal_inst),     // [OUT] (internal exception use)
	.instruction_o  (instruction)           // [OUT] to self (feedback loop)
);


// ----------------------------------------------------------------------------
// Register File Forwarding
// x0 -> 0; WB match -> forward; else -> read from regs[]
// ----------------------------------------------------------------------------

assign reg_rdata1 =
	(src1_select == 5'd0) ? 32'b0 :
	(!wb_stall && wb_alu_to_reg &&
 	(wb_dest_reg_sel == src1_select))
    	? (wb_mem_to_reg ? wb_read_data : wb_result)
    	: regs[src1_select];

assign reg_rdata2 =
	(src2_select == 5'd0) ? 32'b0 :
	(!wb_stall && wb_alu_to_reg &&
 	(wb_dest_reg_sel == src2_select))
    	? (wb_mem_to_reg ? wb_read_data : wb_result)
    	: regs[src2_select];

// ----------------------------------------------------------------------------
// Register File Writeback
// ----------------------------------------------------------------------------

integer i;
always @(posedge clk or posedge reset) begin
	if (reset) begin
    	for (i = 1; i < 32; i = i + 1)
        	regs[i] <= 32'b0;
	end
	else if (wb_alu_to_reg && !stall_read && !wb_stall && wb_dest_reg_sel != 5'd0) begin
    	regs[wb_dest_reg_sel] <=
        	wb_mem_to_reg ? wb_read_data : wb_result;
	end
end


// ----------------------------------------------------------------------------
// Stall Register
// ----------------------------------------------------------------------------

always @(posedge clk or posedge reset) begin
	if (reset)
    	stall_read <= 1'b1;
	else
    	stall_read <= stall;
end

// ----------------------------------------------------------------------------
// Execute Stage
// ----------------------------------------------------------------------------
execute execute (
	.clk          (clk),                   // [IN]  from pipe top
	.reset        (reset),                 // [IN]  from pipe top

	// Inputs from ID/EX
	.reg_rdata1   (reg_rdata1),            // [IN]  from reg file forwarding
	.reg_rdata2   (reg_rdata2),            // [IN]  from reg file forwarding
	.execute_imm  (execute_immediate),     // [IN]  from IF_ID_stage
	.pc           (pc),                    // [IN]  from IF_ID_stage
	.fetch_pc     (fetch_pc),              // [IN]  from pipe PC reg
	.immediate_sel(immediate_sel),         // [IN]  from IF_ID_stage
	.mem_write    (mem_write),             // [IN]  from IF_ID_stage
	.jal          (jal),                   // [IN]  from IF_ID_stage
	.jalr         (jalr),                  // [IN]  from IF_ID_stage
	.lui          (lui),                   // [IN]  from IF_ID_stage
	.alu          (alu),                   // [IN]  from IF_ID_stage
	.branch       (branch),                // [IN]  from IF_ID_stage
	.arithsubtype (arithsubtype),          // [IN]  from IF_ID_stage
	.mem_to_reg   (mem_to_reg),            // [IN]  from IF_ID_stage
	.stall_read   (stall_read),            // [IN]  from pipe stall_read reg
	.dest_reg_sel (dest_reg_sel),          // [IN]  from IF_ID_stage
	.alu_op       (alu_operation),         // [IN]  from IF_ID_stage
	.dmem_raddr   (dmem_read_offset),      // [IN]  from dmem_read_address[1:0]

	// Inputs from WB
	.wb_branch_i      (wb_branch),         // [IN]  from EX->WB reg (loopback)
	.wb_branch_nxt_i  (wb_branch_nxt),     // [IN]  from EX->WB reg (loopback)

	// Outputs EX -> Pipeline
	.alu_operand1 	(alu_operand1),         // [OUT] to dmem_read_addr, wb_stage
	.alu_operand2 	(alu_operand2),         // [OUT] to wb_stage
	.write_address	(write_address),        // [OUT] to wb_stage
	.branch_stall 	(branch_stall),         // [OUT] to PC update logic
	.next_pc      (next_pc),               // [OUT] to PC update logic, next_pc_pipe
	.branch_taken 	(branch_taken),         // [OUT] (internal EX use)

	// Outputs EX -> WB (registered)
	.wb_result           (wb_result),       // [OUT] to IF_ID, reg WB
	.wb_mem_write        (wb_mem_write),    // [OUT] to dmem_write_ready
	.wb_alu_to_reg       (wb_alu_to_reg),   // [OUT] to IF_ID, reg WB
	.wb_dest_reg_sel     (wb_dest_reg_sel), // [OUT] to IF_ID, reg WB
	.wb_branch           (wb_branch),       // [OUT] to wb_stage, self (loopback)
	.wb_branch_nxt       (wb_branch_nxt),   // [OUT] to self (loopback)
	.wb_mem_to_reg       (wb_mem_to_reg),   // [OUT] to IF_ID, wb_stage, reg WB
	.wb_read_address     (wb_read_address), // [OUT] to wb_stage
	.mem_alu_operation   (wb_alu_operation) // [OUT] to wb_stage
);

assign next_pc_pipe = next_pc;

// ----------------------------------------------------------------------------
// PC Update Logic
// ----------------------------------------------------------------------------

always @(posedge clk or posedge reset) begin
	if (reset)
    	fetch_pc <= RESET;
	else if (!stall_read)
    	fetch_pc <= branch_stall
                     	? fetch_pc + 4
                     	: next_pc;
end


// ----------------------------------------------------------------------------
// Write-Back Stage
// ----------------------------------------------------------------------------
wb wb_stage (
   .clk(clk),                              // [IN]  from pipe top
   .reset(reset),                           // [IN]  from pipe top

   // Inputs
   .stall_read_i       (stall_read),        // [IN]  from pipe stall_read reg
   .fetch_pc_i         (fetch_pc),          // [IN]  from pipe PC reg
   .wb_branch_i        (wb_branch),         // [IN]  from execute (EX->WB reg)
   .wb_mem_to_reg_i    (wb_mem_to_reg),     // [IN]  from execute (EX->WB reg)
   .mem_write_i        (mem_write),         // [IN]  from IF_ID_stage
   .write_address_i    (write_address),     // [IN]  from execute
   .alu_operand2_i     (alu_operand2),      // [IN]  from execute
   .alu_operation_i    (alu_operation),     // [IN]  from IF_ID_stage
   .wb_alu_operation_i (wb_alu_operation),  // [IN]  from execute (EX->WB reg)
   .wb_read_address_i  (wb_read_address),   // [IN]  from execute (EX->WB reg)
   .dmem_read_data_i   (dmem_read_data),    // [IN]  from pipe top (ext memory)
   .dmem_write_valid_i (dmem_write_valid),  // [IN]  from pipe top (ext memory)

   // Outputs
   .inst_mem_address_o (inst_mem_address),   // [OUT] to pipe top (IMEM address)
   .inst_mem_is_ready_o(inst_mem_is_ready),  // [OUT] to pipe top
   .wb_stall_o         (wb_stall),           // [OUT] to IF_ID_stage, reg forwarding
   .wb_write_address_o (wb_write_address),   // [OUT] to dmem_write_address
   .wb_write_data_o    (wb_write_data),      // [OUT] to dmem_write_data
   .wb_write_byte_o    (wb_write_byte),      // [OUT] to dmem_write_byte
   .wb_read_data_o     (wb_read_data),       // [OUT] to IF_ID_stage, reg WB
   .inst_fetch_pc_o    (inst_fetch_pc),      // [OUT] to IF_ID_stage, inst_fetch_pc_pipe
   .wb_stall_first_o   (wb_stall_first),     // [OUT] (branch stall cycle 1)
   .wb_stall_second_o  (wb_stall_second)     // [OUT] (branch stall cycle 2)
);
assign inst_fetch_pc_pipe = inst_fetch_pc;

assign pc_out = fetch_pc;

endmodule
