/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: memory_stage.sv
 */



module memory_stage (
    input logic clk,
    input logic rst,

    // Memory interface
    wishbone_interface.master wb,

    // Inputs
    input logic [31:0] source_data_in,
    input logic [31:0] rd_data_in,
    input instruction::t instruction_in,
    input logic [31:0] program_counter_in,
    input logic [31:0] next_program_counter_in,

    // Outputs
    output logic [31:0] source_data_reg_out,
    output logic [31:0] rd_data_reg_out,
    output instruction::t instruction_reg_out,
    output logic [31:0] program_counter_reg_out,
    output logic [31:0] next_program_counter_reg_out,
    output forwarding::t forwarding_out,

    // Pipeline control
    input pipeline_status::forwards_t status_forwards_in,
    output pipeline_status::forwards_t status_forwards_out,
    input pipeline_status::backwards_t status_backwards_in,
    output pipeline_status::backwards_t status_backwards_out,
    input logic [31:0] jump_address_backwards_in,
    output logic [31:0] jump_address_backwards_out
);

  logic [31:0] source_data;
  logic [31:0] rd_data;  //For load rd=mem[rs1+imm], for store rd will be unchanged
  logic [31:0] mem_address;

  logic load_missaligned;
  logic store_missaligned;

  logic load_inst;
  logic store_inst;
  logic branch_inst;

  logic [3:0] word_select;

  assign load_inst = instruction_in.op inside {op::LB, op::LH, op::LW, op::LBU, op::LHU};
  assign store_inst = instruction_in.op inside {op::SB, op::SH, op::SW};
  assign branch_inst = instruction_in.op inside {
      op::BEQ, op::BNE, op::BLT, op::BGE,
      op::BLTU, op::BGEU, op::JAL, op::JALR
  };

  //rd_data = rs1+imm as calculated in execute stage for load and store
  //for store, source_data = rs2_data
  assign mem_address = (load_inst || store_inst) ? rd_data_in : 32'b0;

  //Load/Store misalignment detection
  always_comb begin
    load_missaligned =
        ((instruction_in.op inside {op::LH, op::LHU}) && (mem_address[0] != 1'b0)) || 
        ((instruction_in.op inside {op::LW}) &&  (mem_address[1:0] != 2'b00));

    store_missaligned =
        ((instruction_in.op inside {op::SH}) && (mem_address[0] != 1'b0)) || 
        ((instruction_in.op inside {op::SW}) &&  (mem_address[1:0] != 2'b00));
  end

  // Forwarding logic
  always_comb begin
    if (status_forwards_in == pipeline_status::VALID && instruction_in.rd_address != 5'd0) begin
      if (branch_inst || store_inst) begin
        forwarding_out.data_valid = 1'b0;
        forwarding_out.address = '0;
        forwarding_out.data = '0;

        // For load instructions, we can only forward after the load is complete 
      end else if (load_inst) begin
        if (load_missaligned || load_fault && !stall) begin
          forwarding_out.data_valid = 1'b0;
          forwarding_out.data = '0;
          forwarding_out.address = '0;
        end else begin
          forwarding_out.data_valid = 1'b1;  //valid = load done 
          forwarding_out.address = instruction_in.rd_address;
          // For load instructions, we forward the data read from memory
          forwarding_out.data = read_data_buffer;  //after load done
        end

      end else begin  //for ALU instructions
        forwarding_out.data_valid = 1'b1;
        forwarding_out.address = instruction_in.rd_address;
        forwarding_out.data = rd_data_in;
      end

    end else begin
      forwarding_out.data_valid = 1'b0;
      forwarding_out.data = '0;
      forwarding_out.address = '0;
    end
  end



  //Memory Implementation
  logic read_request_pending;
  logic write_request_pending;

  logic [31:0] read_data_buffer;  // Buffer to hold data read from memory 
  logic load_fault;  //err signal from wishbone for load instructions
  logic store_fault;  //err signal from wishbone for store instructions

  logic stall;

  //
  

    //Select Line
    always_comb begin

    if ((load_inst) || (store_inst)) begin

      unique case (instruction_in.op)
        op::LW, op::SW: word_select = 4'b1111;

        op::LHU, op::LH, op::SH: begin
          unique case (mem_address[1:0])
            2'b00:   word_select = 4'b0011;
            2'b10:   word_select = 4'b1100;
            default: word_select = 4'b0000;  // misaligned
          endcase
        end

        op::LB, op::LBU, op::SB: begin
          unique case (mem_address[1:0])
            2'b00: word_select = 4'b0001;
            2'b01: word_select = 4'b0010;
            2'b10: word_select = 4'b0100;
            2'b11: word_select = 4'b1000;
          endcase
        end

        default: word_select = 4'b0000;
      endcase
    end

    end

    always_ff @(posedge clk) begin
      if (rst) begin
        read_request_pending  <= 0;
        write_request_pending <= 0;
      end else begin
        if (wb.ack || wb.err) begin
          read_request_pending  <= 0;
          write_request_pending <= 0;
        end else if (!read_request_pending && !write_request_pending) begin
          if (load_inst && !load_missaligned) begin
            read_request_pending <= 1;
          end else if (store_inst && !store_missaligned) begin
            write_request_pending <= 1;
          end
        end
      end
    end


    always_comb begin

      wb.cyc = 0;
      wb.stb = 0;
      wb.we = 0;
      wb.adr = 32'b0;
      wb.dat_mosi = 32'b0;
      wb.sel = 4'b0;
      load_fault = 0;
      store_fault = 0;
      stall = 0;

      if (read_request_pending) begin
        wb.cyc = 1;
        wb.stb = 1;
        wb.we  = 0;
        wb.adr = mem_address;
        wb.sel = word_select;

        //data read from memory
        if (wb.ack) begin
          case (instruction_in.op)
            op::LB: read_data_buffer = {{24{wb.dat_miso[7]}}, wb.dat_miso};
            op::LH: read_data_buffer = {{16{wb.dat_miso[15]}}, wb.dat_miso}; 
            op::LBU: read_data_buffer = {{24{0}}, wb.dat_miso};
            op::LHU: read_data_buffer = {{16{0}}, wb.dat_miso};
            default: read_data_buffer = wb.dat_miso;
          endcase
        end

        if (wb.err) begin
          load_fault = 1;  //handle load fault
        end else if (!wb.ack) begin
          stall = 1;  //wait for ack
        end
      end else if (write_request_pending) begin
        wb.cyc = 1;
        wb.stb = 1;
        wb.we = 1;
        wb.adr = mem_address;
        wb.dat_mosi = source_data_in;  //data to be written to memory
        wb.sel = word_select;


        if (wb.err) begin
          store_fault = 1;  //handle store fault
        end else if (!wb.ack) begin
          stall = 1;  //wait for ack
        end
      end
    end

  

  // -----------------------------------------
  // Backward Control Logic
  // -----------------------------------------
  always_comb begin

    status_backwards_out = status_backwards_in;
    jump_address_backwards_out = jump_address_backwards_in;

    if (stall) begin

      status_backwards_out = pipeline_status::STALL;
      jump_address_backwards_out = '0;
    end
 
  end


  // Pipeline registers
  always_ff @(posedge clk) begin

    if (rst) begin
      source_data_reg_out          <= '0;
      rd_data_reg_out              <= '0;
      instruction_reg_out          <= '0;
      program_counter_reg_out      <= constants::RESET_ADDRESS;
      next_program_counter_reg_out <= constants::RESET_ADDRESS + 4;
    end else begin

      case (status_backwards_in)

        pipeline_status::JUMP: begin
          status_forwards_out <= pipeline_status::BUBBLE;  // flush
        end

        pipeline_status::STALL: begin
          // hold 
        end
        pipeline_status::READY: begin

          if(status_forwards_in inside {
                pipeline_status::FETCH_FAULT,
                pipeline_status::ILLEGAL_INSTRUCTION,
                pipeline_status::ECALL,
                pipeline_status::EBREAK,
                pipeline_status::FETCH_MISALIGNED,
                pipeline_status::BUBBLE
                }) begin

            status_forwards_out <= status_forwards_in;
            program_counter_reg_out <= program_counter_in;

          end else if (status_forwards_in == pipeline_status::VALID) begin

            if (load_missaligned || store_missaligned || load_fault || store_fault) begin
              status_forwards_out <= load_missaligned ? pipeline_status::LOAD_MISALIGNED :
                                     store_missaligned ? pipeline_status::STORE_MISALIGNED :
                                     load_fault ? pipeline_status::LOAD_FAULT :
                                     pipeline_status::STORE_FAULT;
              program_counter_reg_out <= program_counter_in;
            end
            begin
              status_forwards_out <= pipeline_status::VALID;
              source_data_reg_out <= source_data_in;  //For CSR :: TODO
              rd_data_reg_out <= (load_inst) ? read_data_buffer : rd_data_in;
              instruction_reg_out <= instruction_in;
              program_counter_reg_out <= program_counter_in;
              next_program_counter_reg_out <= next_program_counter_in;

            end

          end



        end



      endcase



    end

  end



endmodule
