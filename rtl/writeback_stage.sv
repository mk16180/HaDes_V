/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: writeback_stage.sv
 */



module writeback_stage (
    input logic clk,
    input logic rst,

    // Inputs
    input logic [31:0]   source_data_in,
    input logic [31:0]   rd_data_in,
    input instruction::t instruction_in,
    input logic [31:0]   program_counter_in,
    input logic [31:0]   next_program_counter_in,

    // Interrupt signals
    input logic external_interrupt_in,
    input logic timer_interrupt_in,

    // Outputs
    output forwarding::t forwarding_out,

    // Pipeline control
    input  pipeline_status::forwards_t  status_forwards_in,
    output pipeline_status::backwards_t status_backwards_out,
    output logic [31:0] jump_address_backwards_out
);

trap_field::tf trap_field;

logic [31:0] mtvec_out;
logic [31:0] mepc_out;
logic interrupt_jump;
logic interrupt_pending;
logic [31:0] csr_data; //data recieved from csr reg during csr intstruction
logic [31:0] rd_data; // rd_data = csr_data (CSR inst) else rd_data_in


csr_box csr_box_inst (
    .clk(clk),
    .rst(rst),

    .instruction_in(instruction_in),
    .next_pc_in(next_program_counter_in),
    .trap_in(trap_field),
    .status_forwards_in(status_forwards_in),

    .external_interrupt_in(external_interrupt_in),
    .timer_interrupt_in(timer_interrupt_in),

    .source_data_in(source_data_in),
    // Outputs
    .source_data_out(csr_data),
    .interrupt_pending(interrupt_pending),
    .mtvec_out(mtvec_out),
    .mepc_out(mepc_out)

);

    //Handling Traps and interrupts
    always_comb begin

        // defaults
        trap_field = '0;
        trap_field.excep_type = exception::NONE;

        unique case (status_forwards_in)
            pipeline_status::FETCH_MISALIGNED   : trap_field.excep_type = exception::FETCH_MISALIGNED;
            pipeline_status::FETCH_FAULT        : trap_field.excep_type = exception::FETCH_FAULT;
            pipeline_status::ILLEGAL_INSTRUCTION: trap_field.excep_type = exception::ILLEGAL_INSTRUCTION;
            pipeline_status::LOAD_MISALIGNED    : trap_field.excep_type = exception::LOAD_MISALIGNED;
            pipeline_status::LOAD_FAULT         : trap_field.excep_type = exception::LOAD_FAULT;
            pipeline_status::STORE_MISALIGNED   : trap_field.excep_type = exception::STORE_MISALIGNED;
            pipeline_status::STORE_FAULT        : trap_field.excep_type = exception::STORE_FAULT;
            pipeline_status::ECALL              : trap_field.excep_type = exception::ECALL;
            pipeline_status::EBREAK             : trap_field.excep_type = exception::EBREAK;
            default                             : trap_field.excep_type = exception::NONE;
        endcase

        if(trap_field.excep_type != exception::NONE) begin
            trap_field.valid = 1'b1;
            trap_field.pc = program_counter_in;
        end else begin
            trap_field.valid = 1'b0;
        end

        interrupt_jump = (external_interrupt_in || timer_interrupt_in) && interrupt_pending;

    end

    always_comb begin
    // Default
    status_backwards_out       = pipeline_status::READY;
    jump_address_backwards_out = '0;
    interrupt_jump             = (external_interrupt_in || timer_interrupt_in) && interrupt_pending;

    if (trap_field.valid) begin
        // Exception always takes priority
        status_backwards_out       = pipeline_status::JUMP;
        jump_address_backwards_out = mtvec_out;
    end
    else if (status_forwards_in == pipeline_status::VALID) begin
        if (instruction_in.op == op::MRET) begin
            status_backwards_out       = pipeline_status::JUMP;
            jump_address_backwards_out = mepc_out;
        end
        else if (instruction_in.op == op::FENCE_I) begin
            status_backwards_out       = pipeline_status::JUMP;
            jump_address_backwards_out = next_program_counter_in;
        end
        else if (interrupt_jump) begin
            // Interrupt checked after MRET/FENCE.I with updated CSR values
            status_backwards_out       = pipeline_status::JUMP;
            jump_address_backwards_out = mtvec_out;
        end
    end
    else if (interrupt_jump && status_forwards_in != pipeline_status::BUBBLE) begin 
        status_backwards_out       = pipeline_status::JUMP;
        jump_address_backwards_out = mtvec_out;
    end
end


    //If there is csr instruction then rd_data = csr_data else rd_data = data_in

    always_comb begin
        rd_data = rd_data_in; // default

        if (instruction_in.op inside
            {op::CSRRW, op::CSRRS, op::CSRRC,
            op::CSRRWI, op::CSRRSI, op::CSRRCI}) begin
            rd_data = csr_data;
        end
    end


  //----------
  // Forwarding Logic
  //----------
  always_comb begin

    // Default
    forwarding_out.data_valid = 1'b0;
    forwarding_out.data = 32'b0;
    forwarding_out.address = 5'b0;

    if (status_forwards_in == pipeline_status::VALID && instruction_in.rd_address != 5'd0) begin
        forwarding_out.data_valid = 1'b1;
        forwarding_out.data = rd_data;
        forwarding_out.address = instruction_in.rd_address;
    end

  end


endmodule
