/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: cpu.sv
 */



module cpu (
    input logic clk,
    input logic rst,

    wishbone_interface.master memory_fetch_port,
    wishbone_interface.master memory_mem_port,

    input logic external_interrupt_in,
    input logic timer_interrupt_in
);



    logic [31:0] instruction_f_out;
    logic [31:0] pc_f_out;

    pipeline_status::forwards_t  status_fwd_f_out;
    pipeline_status::backwards_t status_bwd_f_in;

    logic [31:0] jump_addr_f_in; //jump addr from decode to fetch stage

    //Fetch stage
    fetch_stage fetch_stage_inst(
        .clk(clk),
        .rst(rst),

        .wb(memory_fetch_port),  //Wishbone interface for fetch stage

        .instruction_reg_out(instruction_f_out), //Instruction output to decode stage
        .program_counter_reg_out(pc_f_out), //Program counter output to decode stage

        .status_forwards_out(status_fwd_f_out), //Forwarding status output to decode stage
        .status_backwards_in(status_bwd_f_in), //Backwarding status input from decode stage

        .jump_address_backwards_in(jump_addr_f_in) //Jump address input from decode stage

    );

    forwarding::t ex_fwd_d_in; //fwd from ex to decode stage
    forwarding::t mem_fwd_d_in; //fwd from mem to decode stage
    forwarding::t wb_fwd_d_in; //fwd from wb to decode stage

    

    logic [31:0] rs1_data_d_out; 
    logic [31:0] rs2_data_d_out;
    logic [31:0] pc_d_out;
    instruction::t instruction_d_out;
    logic [31:0] jump_addr_d_in; //jump addr from ex to decode stage

    pipeline_status::forwards_t status_fwd_d_out;
    pipeline_status::backwards_t status_bwd_d_in;

    //Decode stage
    decode_stage decode_stage_inst(
        .clk(clk),
        .rst(rst),

        .instruction_in(instruction_f_out),
        .program_counter_in(pc_f_out),

        .exe_forwarding_in(ex_fwd_d_in),
        .mem_forwarding_in(mem_fwd_d_in),
        .wb_forwarding_in(wb_fwd_d_in),

        .rs1_data_reg_out(rs1_data_d_out),
        .rs2_data_reg_out(rs2_data_d_out),
        .program_counter_reg_out(pc_d_out),
        .instruction_reg_out(instruction_d_out),

        .status_forwards_in(status_fwd_f_out),
        .status_forwards_out(status_fwd_d_out),
        .status_backwards_in(status_bwd_d_in),
        .status_backwards_out(status_bwd_f_in),

        .jump_address_backwards_in(jump_addr_d_in),
        .jump_address_backwards_out(jump_addr_f_in)

    );

    pipeline_status::forwards_t status_fwd_ex_out;
    pipeline_status::backwards_t status_bwd_ex_in; 

    logic [31:0] jump_addr_ex_in; //jump addr from decode to execute stage
    logic [31:0] source_data_ex_out; //source data from execute stage
    logic [31:0] rd_data_ex_out; //rd data from execute stage
    instruction::t instruction_ex_out; //instruction from execute stage
    logic [31:0] program_counter_ex_out; //program counter from execute stage
    logic [31:0] next_program_counter_ex_out; //next program counter from execute stage
    

    //Execute stage
    execute_stage execute_stage_inst(
        .clk(clk),
        .rst(rst),

        .rs1_data_in(rs1_data_d_out),
        .rs2_data_in(rs2_data_d_out),
        .instruction_in(instruction_d_out),
        .program_counter_in(pc_d_out), 

        .source_data_reg_out(source_data_ex_out),
        .rd_data_reg_out(rd_data_ex_out),
        .instruction_reg_out(instruction_ex_out),
        .program_counter_reg_out(program_counter_ex_out),
        .next_program_counter_reg_out(next_program_counter_ex_out),
        .forwarding_out(ex_fwd_d_in),



        //Pipeline control 
        .status_forwards_in(status_fwd_d_out),
        .status_forwards_out(status_fwd_ex_out), 
        .status_backwards_in(status_bwd_ex_in),
        .status_backwards_out(status_bwd_d_in),

        .jump_address_backwards_in(jump_addr_ex_in),
        .jump_address_backwards_out(jump_addr_d_in)


    );

    pipeline_status::forwards_t status_fwd_mem_out;
    pipeline_status::backwards_t status_bwd_mem_in;

    logic [31:0] jump_addr_mem_in; //jump addr from Writeback to Memory stage
    logic [31:0] source_data_mem_out; //source data from Memory stage
    logic [31:0] rd_data_mem_out; //rd data from Memory stage
    instruction::t instruction_mem_out; //instruction from Memory stage
    logic [31:0] program_counter_mem_out; //program counter from Memory stage
    logic [31:0] next_pc_mem_out; //next program counter from Memory stage
    

    //Memory stage
    memory_stage memory_stage_inst(
        .clk(clk),
        .rst(rst),

        .wb(memory_mem_port),

        .source_data_in(source_data_ex_out),
        .rd_data_in(rd_data_ex_out),
        .instruction_in(instruction_ex_out),
        .program_counter_in(program_counter_ex_out),
        .next_program_counter_in(next_program_counter_ex_out),

        .source_data_reg_out(source_data_mem_out),
        .rd_data_reg_out(rd_data_mem_out),
        .instruction_reg_out(instruction_mem_out),
        .program_counter_reg_out(program_counter_mem_out),
        .next_program_counter_reg_out(next_pc_mem_out),
        .forwarding_out(mem_fwd_d_in),

        //Pipeline control 
        .status_forwards_in(status_fwd_ex_out),
        .status_forwards_out(status_fwd_mem_out),
        .status_backwards_in(status_bwd_mem_in),
        .status_backwards_out(status_bwd_ex_in),
        .jump_address_backwards_in(jump_addr_mem_in),
        .jump_address_backwards_out(jump_addr_ex_in)


    );

    //Writeback stage
    writeback_stage writeback_stage_inst(
        .clk(clk),
        .rst(rst),

        .source_data_in(source_data_mem_out),
        .rd_data_in(rd_data_mem_out),
        .instruction_in(instruction_mem_out),
        .program_counter_in(program_counter_mem_out),
        .next_program_counter_in(next_pc_mem_out),

        .external_interrupt_in(external_interrupt_in),
        .timer_interrupt_in(timer_interrupt_in),

        //Pipeline control 
        .forwarding_out(wb_fwd_d_in),
        .status_forwards_in(status_fwd_mem_out),
        .status_backwards_out(status_bwd_mem_in),
        .jump_address_backwards_out(jump_addr_mem_in)

    );





endmodule
