// ----------------------------------------------------------------------------
// Stage 1: Instruction Fetch and Decode (IF_ID)
// Handles instruction fetching, immediate generation, exception detection,
// and instantiates the ID -> EX pipeline register.
// ----------------------------------------------------------------------------
module IF_ID
#(
    parameter [31:0] RESET = 32'h0000_0000
)
(
    input                   clk,
    input                   reset,
    input                   stall,
    output reg              exception,

    // Instruction memory interface
    input                   inst_mem_is_valid,
    input  [31:0]           inst_mem_read_data,

    // Pipeline feedback signals
    input                   stall_read_i,       // Active-low stall
    input  [31:0]           inst_fetch_pc,      // PC of current fetch
    input  [31:0]           instruction_i,      // Current ID-stage instruction

    // WB-stage forwarding inputs
    input                   wb_stall,
    input                   wb_alu_to_reg,
    input                   wb_mem_to_reg,
    input  [4:0]            wb_dest_reg_sel,
    input  [31:0]           wb_result,
    input  [31:0]           wb_read_data,

    // Instruction memory address
    input  [1:0]            inst_mem_offset,    // PC[1:0] for alignment check

    // EX-bound outputs (via ID->EX pipeline register)
    output [31:0] execute_immediate_w,  // Sign-extended immediate
    output        immediate_sel_w,      // Select immediate vs RS2
    output        alu_w,                // ALU instruction flag
    output        lui_w,                // LUI flag
    output        jal_w,                // JAL flag
    output        jalr_w,              // JALR flag
    output        branch_w,             // Branch flag
    output        mem_write_w,          // Store flag
    output        mem_to_reg_w,         // Load flag
    output        arithsubtype_w,       // SUB/SRA subtype (bit 30)
    output [31:0] pc_w,                 // EX-stage PC
    output [4:0]  src1_select_w,        // RS1 index
    output [4:0]  src2_select_w,        // RS2 index
    output [4:0]  dest_reg_sel_w,       // RD index
    output [2:0]  alu_operation_w,      // ALU op from func3
    output        illegal_inst_w,       // Invalid opcode flag
    output [31:0] instruction_o         // Forwarded instruction to pipeline
);

`include "opcode.vh"

// Internal signals
reg  [31:0] immediate;
reg         illegal_inst;

// ----------------------------------------------------------------------------
// IF Stage: Inject NOP on stall, otherwise pass fetched instruction
// ----------------------------------------------------------------------------

assign instruction_o = stall_read_i ? NOP : inst_mem_read_data;

// ----------------------------------------------------------------------------
// Exception Detection (illegal instruction or misaligned fetch)
// ----------------------------------------------------------------------------

always @(posedge clk or posedge reset) begin
    if (reset)
        exception <= 1'b0;
    else if (illegal_inst || inst_mem_offset != 2'b00)
        exception <= 1'b1;
    else
        exception <= 1'b0;
end

// ----------------------------------------------------------------------------
// ID Stage: Immediate Generation
// ----------------------------------------------------------------------------

always @(*) begin
    immediate    = 32'h0;
    illegal_inst = 1'b0;

    case (instruction_i[`OPCODE])
        // I-type: imm[11:0] sign-extended
        JALR  : immediate = {{20{instruction_i[31]}}, instruction_i[31:20]};

        // B-type: imm[12|10:5|4:1|11], LSB=0
        BRANCH: immediate = {{20{instruction_i[31]}}, instruction_i[7], instruction_i[30:25], instruction_i[11:8], 1'b0};

        // I-type: imm[11:0] sign-extended
        LOAD  : immediate = {{20{instruction_i[31]}}, instruction_i[31:20]};

        // S-type: imm[11:5|4:0] sign-extended
        STORE : immediate = {{20{instruction_i[31]}}, instruction_i[31:25], instruction_i[11:7]};

        // I-type: shift uses shamt[4:0], others sign-extended
        ARITHI: immediate =
                 (instruction_i[`FUNC3] == SLL ||
                  instruction_i[`FUNC3] == SR)
                 ? {27'b0, instruction_i[24:20]}
                 : {{20{instruction_i[31]}}, instruction_i[31:20]};

        // R-type: no immediate
        ARITHR: immediate = 32'h0;

        // U-type: imm[31:12], lower 12 bits zeroed
        LUI   : immediate = {instruction_i[31:12], 12'b0};

        // J-type: imm[20|10:1|11|19:12], LSB=0
        JAL   : immediate = {{12{instruction_i[31]}}, instruction_i[19:12], instruction_i[20], instruction_i[30:21], 1'b0};

        default: illegal_inst = 1'b1;
    endcase
end

// ----------------------------------------------------------------------------
// ID -> EX Pipeline Register
// ----------------------------------------------------------------------------

id_ex_reg u_id_ex (
    .clk            (clk),                  // [IN]  from IF_ID top
    .reset          (reset),                // [IN]  from IF_ID top
    .stall_n        (stall_read_i),         // [IN]  from pipe (active-low stall)

    // Inputs from ID decode logic
    .immediate_i    (immediate),            // [IN]  from imm gen combinational
    .immediate_sel_i(                       // [IN]  from opcode decode
        (instruction_i[`OPCODE] == JALR)  || (instruction_i[`OPCODE] == LOAD)  ||
        (instruction_i[`OPCODE] == ARITHI)
    ),
    .alu_i          (                       // [IN]  from opcode decode
        (instruction_i[`OPCODE] == ARITHI) || (instruction_i[`OPCODE] == ARITHR)
    ),
    .lui_i          (instruction_i[`OPCODE] == LUI),    // [IN]  from opcode decode
    .jal_i          (instruction_i[`OPCODE] == JAL),    // [IN]  from opcode decode
    .jalr_i         (instruction_i[`OPCODE] == JALR),   // [IN]  from opcode decode
    .branch_i       (instruction_i[`OPCODE] == BRANCH), // [IN]  from opcode decode
    .mem_write_i    (instruction_i[`OPCODE] == STORE),  // [IN]  from opcode decode
    .mem_to_reg_i   (instruction_i[`OPCODE] == LOAD),   // [IN]  from opcode decode
    .arithsubtype_i (                       // [IN]  from opcode/func decode
        instruction_i[`SUBTYPE] &&
        !(instruction_i[`OPCODE] == ARITHI &&
          instruction_i[`FUNC3] == ADD)
    ),
    .pc_i           (inst_fetch_pc),        // [IN]  from pipe (fetch PC)
    .src1_sel_i     (instruction_i[`RS1]),  // [IN]  from instruction field
    .src2_sel_i     (instruction_i[`RS2]),  // [IN]  from instruction field
    .dest_reg_sel_i (instruction_i[`RD]),   // [IN]  from instruction field
    .alu_op_i       (instruction_i[`FUNC3]),// [IN]  from instruction field
    .illegal_inst_i (illegal_inst),         // [IN]  from imm gen default case

    // Registered outputs to EX stage (wires back to IF_ID ports)
    .execute_immediate_o (execute_immediate_w), // [OUT] to pipe execute_immediate
    .immediate_sel_o     (immediate_sel_w),     // [OUT] to pipe immediate_sel
    .alu_o               (alu_w),               // [OUT] to pipe alu
    .lui_o               (lui_w),               // [OUT] to pipe lui
    .jal_o               (jal_w),               // [OUT] to pipe jal
    .jalr_o              (jalr_w),              // [OUT] to pipe jalr
    .branch_o            (branch_w),            // [OUT] to pipe branch
    .mem_write_o         (mem_write_w),         // [OUT] to pipe mem_write
    .mem_to_reg_o        (mem_to_reg_w),        // [OUT] to pipe mem_to_reg
    .arithsubtype_o      (arithsubtype_w),      // [OUT] to pipe arithsubtype
    .pc_o                (pc_w),                // [OUT] to pipe pc
    .src1_sel_o          (src1_select_w),       // [OUT] to pipe src1_select
    .src2_sel_o          (src2_select_w),       // [OUT] to pipe src2_select
    .dest_reg_sel_o      (dest_reg_sel_w),      // [OUT] to pipe dest_reg_sel
    .alu_op_o            (alu_operation_w),     // [OUT] to pipe alu_operation
    .illegal_inst_o      (illegal_inst_w)       // [OUT] to pipe illegal_inst
);
endmodule


// ----------------------------------------------------------------------------
// ID -> EX Pipeline Register Module
// ----------------------------------------------------------------------------

module id_ex_reg (
    input         clk,
    input         reset,
    input         stall_n,

    // Inputs from ID
    input  [31:0] immediate_i,
    input         immediate_sel_i,
    input         alu_i,
    input         lui_i,
    input         jal_i,
    input         jalr_i,
    input         branch_i,
    input         mem_write_i,
    input         mem_to_reg_i,
    input         arithsubtype_i,
    input  [31:0] pc_i,
    input  [4:0]  src1_sel_i,
    input  [4:0]  src2_sel_i,
    input  [4:0]  dest_reg_sel_i,
    input  [2:0]  alu_op_i,
    input         illegal_inst_i,

    // Outputs to EX
    output reg [31:0] execute_immediate_o,
    output reg        immediate_sel_o,
    output reg        alu_o,
    output reg        lui_o,
    output reg        jal_o,
    output reg        jalr_o,
    output reg        branch_o,
    output reg        mem_write_o,
    output reg        mem_to_reg_o,
    output reg        arithsubtype_o,
    output reg [31:0] pc_o,
    output reg [4:0]  src1_sel_o,
    output reg [4:0]  src2_sel_o,
    output reg [4:0]  dest_reg_sel_o,
    output reg [2:0]  alu_op_o,
    output reg        illegal_inst_o
);

always @(posedge clk or posedge reset) begin
    if (reset) begin
        execute_immediate_o <= 32'h0;
        immediate_sel_o     <= 1'b0;
        alu_o               <= 1'b0;
        lui_o               <= 1'b0;
        jal_o               <= 1'b0;
        jalr_o              <= 1'b0;
        branch_o            <= 1'b0;
        mem_write_o         <= 1'b0;
        mem_to_reg_o        <= 1'b0;
        arithsubtype_o      <= 1'b0;
        pc_o                <= 32'h0;
        src1_sel_o          <= 5'h0;
        src2_sel_o          <= 5'h0;
        dest_reg_sel_o      <= 5'h0;
        alu_op_o            <= 3'h0;
        illegal_inst_o      <= 1'b0;
    end
    else if (!stall_n) begin
        execute_immediate_o <= immediate_i;
        immediate_sel_o     <= immediate_sel_i;
        alu_o               <= alu_i;
        lui_o               <= lui_i;
        jal_o               <= jal_i;
        jalr_o              <= jalr_i;
        branch_o            <= branch_i;
        mem_write_o         <= mem_write_i;
        mem_to_reg_o        <= mem_to_reg_i;
        arithsubtype_o      <= arithsubtype_i;
        pc_o                <= pc_i;
        src1_sel_o          <= src1_sel_i;
        src2_sel_o          <= src2_sel_i;
        dest_reg_sel_o      <= dest_reg_sel_i;
        alu_op_o            <= alu_op_i;
        illegal_inst_o      <= illegal_inst_i;
    end
end

endmodule
