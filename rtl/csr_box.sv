


module csr_box (

    input logic clk,
    input logic rst,

    // CSR Instruction
    input instruction::t instruction_in,
    input trap_field::tf trap_in,
    input logic [31:0] next_pc_in,
    input pipeline_status::forwards_t status_forwards_in,

    input logic external_interrupt_in,
    input logic timer_interrupt_in,

    input logic [31:0] source_data_in,

    output logic [31:0] source_data_out,
    output logic interrupt_pending, //if this is high, then processor will jump to mtvec address and execute the trap handler
    output logic [31:0] mtvec_out,
    output logic [31:0] mepc_out
);

assign mtvec_out = mtvec;
assign mepc_out = mepc;


// -----------------------------------------------------------------------------
// Machine Information Registers (Read-Only)
// -----------------------------------------------------------------------------

logic [63:0] mcycle;      // Counts elapsed clock cycles (RW)

logic [31:0] mvendorid;   // 0 as no vendor information is implemented (RO)
logic [31:0] marchid;     // 0 as no architecture ID is implemented (RO)
logic [31:0] mimpid;      // 0 as no implementation versioning is used (RO)
logic [31:0] mhartid;     // 0 as HaDes-V currently supports only one hart/core (RO)
logic [31:0] mconfigptr;  // 0 as no configuration structure is implemented (RO)

assign mvendorid = 32'b0;
assign marchid = 32'b0;
assign mimpid = 32'b0;
assign mhartid = 32'b0;
assign mconfigptr = 32'b0;


// -----------------------------------------------------------------------------
// Machine Trap Setup Registers
// -----------------------------------------------------------------------------

logic [31:0] mstatus;     // Stores machine interrupt state bits like MIE/MPIE (RW)
logic [31:0] mie;         // Stores individual interrupt enable bits (RW)
logic [31:0] mtvec;       // Stores jump address for traps/exceptions (RW)  //when the program will get start, mtvec will get the address of trap handler
logic [31:0] misa;        // MXL=01| WARL=000 | EXT=I(8th bit) (RO)
logic [31:0] medeleg;     // 0
logic [31:0] mideleg;     // 0
logic [31:0] mcounteren;  // 0
logic [31:0] mstatush;    // 0

logic [31:0] minstret;

assign misa = 32'h40000100;
assign medeleg = 32'b0;
assign mideleg = 32'b0;
assign mcounteren = 32'b0;
assign mstatush = 32'b0;


// -----------------------------------------------------------------------------
// Machine Trap Handling Registers
// -----------------------------------------------------------------------------

logic [31:0] mscratch;    // Temporary storage used by trap handler software (RW)
logic [31:0] mepc;        // Stores PC of interrupted/faulting instruction (RW)
logic [31:0] mcause;      // Stores exception or interrupt cause code (RW)
logic [31:0] mtval;       // Stores faulting address/instruction if required (RW)
logic [31:0] mip;         // Stores pending interrupt status bits (RO)

logic [31:0] next_mepc;
logic [31:0] next_mcause;
logic next_mstatus_mpie;
logic next_mstatus_mie;
logic [31:0] next_mstatus;

assign mtval = 32'b0; // Not in Hades-V


// Set MEIP and MTIP bits in MIP for external and timer interrupts
assign mip = {20'b0, external_interrupt_in, 3'b0, timer_interrupt_in, 7'b0};




//assign mstatus[3] = mstatus[3]; // MIE bit is at position 3
//assign mstatus[7] = mstatus[7]; // MPIE bit is at position 7

/* 
mip[11] = MEIP  (Machine External Interrupt Pending)  
mie[11] = MEIE  (Machine External Interrupt Enable)   
mip[7]  = MTIP  (Machine Timer Interrupt Pending)     
mie[7]  = MTIE  (Machine Timer Interrupt Enable)      
mstatus[3] = MIE (Global interrupt enable)             */

// An interrupt is pending if it's enabled in MIE and the corresponding bit in MIP is set, and global interrupts are enabled (MIE bit in MSTATUS)  
//assign interrupt_pending = ((mip[11] & mie[11]) | (mip[7] & mie[7])) & mstatus[3];

// For MRET, interrupt eligibility must be checked using MPIE instead of MIE,
// since MRET restores MIE <= MPIE. Using MIE here would delay interrupt
// recognition by one cycle and violate the RISC-V/HaDes-V MRET behavior.

assign interrupt_pending =
    ((mip[11] & mie[11]) | (mip[7] & mie[7])) &
    (instruction_in.op == op::MRET ? mstatus[7] : mstatus[3]) &
    (status_forwards_in != pipeline_status::BUBBLE);   //no bubble


always_comb begin

    next_mepc            = mepc;
    next_mcause          = mcause;
    next_mstatus_mie     = mstatus[3];
    next_mstatus_mpie    = mstatus[7];
    next_mstatus         = {24'b0, mstatus[7], 3'b0, mstatus[3], 3'b0}; 

    if (trap_in.valid) begin
        next_mepc = trap_in.epc;
        next_mcause = (trap_in.excep_type == exception::ECALL) ? 32'hB :
                    (trap_in.excep_type == exception::EBREAK) ? 32'h3 :
                    (trap_in.excep_type == exception::FETCH_MISALIGNED) ? 32'h4 :
                    (trap_in.excep_type == exception::FETCH_FAULT) ? 32'h5 :
                    (trap_in.excep_type == exception::ILLEGAL_INSTRUCTION) ? 32'h2 :
                    (trap_in.excep_type == exception::LOAD_MISALIGNED) ? 32'h6 :
                    (trap_in.excep_type == exception::LOAD_FAULT) ? 32'h7 :
                    (trap_in.excep_type == exception::STORE_MISALIGNED) ? 32'h8 :
                    (trap_in.excep_type == exception::STORE_FAULT) ? 32'h9 :
                        32'h0; // Default case, should not happen

        next_mstatus_mpie = mstatus[3]; // Save current MIE to MPIE
        next_mstatus_mie = 1'b0; // Disable interrupts on trap entry
    end

    //Mret Handling
    else if (instruction_in.op == op::MRET)begin

        next_mstatus_mie = mstatus[7]; // Restore MIE from MPIE
        next_mstatus_mpie = 1'b1; // set MPIE after restoring MIE   //

    end
    //Interrupt handling 
    else if (interrupt_pending) begin

        // Interrupts save NEXT PC
        next_mepc = next_pc_in;

        // External interrupt has priority
        if (mip[11] && mie[11] && mstatus[3])
            next_mcause = 32'h8000000B;

        else if (mip[7] && mie[7] && mstatus[3])
            next_mcause = 32'h80000007;

        // Trap entry
        next_mstatus_mpie = mstatus[3];
        next_mstatus_mie  = 1'b0;

    end
end

logic [31:0] mcycle_curr;
logic [31:0] minstret_curr;

assign mcycle_curr = mcycle[31:0];
assign minstret_curr = minstret[31:0];

// CSR Instruction Handling

always_ff @(posedge clk) begin
    if (rst) begin
        mstatus  <= 32'b0;
        mie      <= 32'b0;
        mtvec    <= 32'b0;
        mscratch <= 32'b0;
        mepc     <= 32'b0;
        mcause   <= 32'b0;
        mcycle   <= 64'b0;
        minstret <= 64'b0;
    end
    else begin
        // Trap handling (only fires when trap_in valid)
        mepc             <= next_mepc;
        mcause           <= next_mcause;
        mstatus[7]     <= next_mstatus_mpie;
        mstatus[3]      <= next_mstatus_mie;
        mstatus          <= {24'b0, next_mstatus[7], 3'b0, next_mstatus[3], 3'b0};

        // Hardware counters
       // mcycle <= mcycle + 1;
       // if (status_forwards_in != pipeline_status::BUBBLE)
       //     minstret <= minstret + 1;

       // Hardware counters
        if (!(instruction_in.op inside {op::CSRRW, op::CSRRS, op::CSRRC,
                                        op::CSRRWI, op::CSRRSI, op::CSRRCI}
            && instruction_in.csr inside {csr::MCYCLE, csr::MCYCLEH}))
            mcycle <= mcycle + 1;

        if (status_forwards_in != pipeline_status::BUBBLE &&
            !(instruction_in.op inside {op::CSRRW, op::CSRRS, op::CSRRC,
                                        op::CSRRWI, op::CSRRSI, op::CSRRCI}
            && instruction_in.csr inside {csr::MINSTRET, csr::MINSTRETH}))
            minstret <= minstret + 1;



        // CSR instruction handling
        case (instruction_in.op)
            // ------- WRITE -------
            op::CSRRW, op::CSRRWI: begin
                case (instruction_in.csr)
                    csr::MSTATUS:  mstatus  <= {24'b0, source_data_in[7], 3'b0, source_data_in[3], 3'b0};
                    csr::MIE:      mie      <= {20'b0, source_data_in[11], 3'b0, source_data_in[7], 7'b0};
                    csr::MTVEC:    mtvec    <= {source_data_in[31:2], 2'b00};
                    csr::MSCRATCH: mscratch <= source_data_in;
                    csr::MEPC:     mepc     <= {source_data_in[31:2], 2'b00};
                    csr::MCAUSE:   mcause   <= source_data_in;
                   // csr::MCYCLE:   mcycle[31:0]   <= source_data_in;
                    csr::MCYCLEH:  mcycle[63:32]  <= source_data_in;
                   // csr::MINSTRET: minstret[31:0]  <= source_data_in;
                    csr::MINSTRETH:minstret[63:32] <= source_data_in;
                    default: begin end
                endcase
            end

            // ------- SET bits -------
            op::CSRRS, op::CSRRSI: begin
                case (instruction_in.csr)
                    csr::MSTATUS:  mstatus  <= mstatus  | {24'b0, source_data_in[7], 3'b0, source_data_in[3], 3'b0};
                    csr::MIE:      mie      <= mie      | {20'b0, source_data_in[11], 3'b0, source_data_in[7], 7'b0};
                    csr::MTVEC:    mtvec    <= mtvec    | {source_data_in[31:2], 2'b00};
                    csr::MSCRATCH: mscratch <= mscratch | source_data_in;
                    csr::MEPC:     mepc     <= mepc     | {source_data_in[31:2], 2'b00};
                    csr::MCAUSE:   mcause   <= mcause   | source_data_in;
                   // csr::MCYCLE:   mcycle[31:0]    <= mcycle[31:0]    | source_data_in;
                    csr::MCYCLEH:  mcycle[63:32]   <= mcycle[63:32]   | source_data_in;
                  //  csr::MINSTRET: minstret[31:0]  <= minstret[31:0]  | source_data_in;
                    csr::MINSTRETH:minstret[63:32] <= minstret[63:32] | source_data_in;
                    default: begin end
                endcase
            end

            // ------- CLEAR bits -------
            op::CSRRC, op::CSRRCI: begin
                case (instruction_in.csr)
                    csr::MSTATUS:  mstatus  <= mstatus  & ~{24'b0, source_data_in[7], 3'b0, source_data_in[3], 3'b0};
                    csr::MIE:      mie      <= mie      & ~{20'b0, source_data_in[11], 3'b0, source_data_in[7], 7'b0};
                    csr::MTVEC:    mtvec    <= mtvec    & ~{source_data_in[31:2], 2'b00};
                    csr::MSCRATCH: mscratch <= mscratch & ~source_data_in;
                    csr::MEPC:     mepc     <= mepc     & ~{source_data_in[31:2], 2'b00};
                    csr::MCAUSE:   mcause   <= mcause   & ~source_data_in;
                  //  csr::MCYCLE:   mcycle[31:0]    <= mcycle[31:0]    & ~source_data_in;
                    csr::MCYCLEH:  mcycle[63:32]   <= mcycle[63:32]   & ~source_data_in;
                  //  csr::MINSTRET: minstret[31:0]  <= minstret[31:0]  & ~source_data_in;
                    csr::MINSTRETH:minstret[63:32] <= minstret[63:32] & ~source_data_in;
                    default: begin end
                endcase
            end

            default: begin end
        endcase
    end
end

logic [31:0] source_data_out_new;
// CSR Read (combinational)
always_comb begin
    source_data_out_new = 32'b0;
    case (instruction_in.csr)
        csr::MVENDORID:  source_data_out_new = mvendorid;
        csr::MARCHID:    source_data_out_new = marchid;
        csr::MIMPID:     source_data_out_new = mimpid;
        csr::MHARTID:    source_data_out_new = mhartid;
        csr::MCONFIGPTR: source_data_out_new = mconfigptr;
        csr::MSTATUS:    source_data_out_new = mstatus;
        csr::MISA:       source_data_out_new = misa;
        csr::MEDELEG:    source_data_out_new = medeleg;
        csr::MIDELEG:    source_data_out_new = mideleg;
        csr::MIE:        source_data_out_new = mie;
        csr::MTVEC:      source_data_out_new = mtvec;
        csr::MCOUNTEREN: source_data_out_new = mcounteren;
        csr::MSTATUSH:   source_data_out_new = mstatush;
        csr::MSCRATCH:   source_data_out_new = mscratch;
        csr::MEPC:       source_data_out_new = mepc;
        csr::MCAUSE:     source_data_out_new = mcause;
        csr::MTVAL:      source_data_out_new = mtval;
        csr::MIP:        source_data_out_new = mip;
        csr::MCYCLE:     source_data_out_new = mcycle[31:0];
        csr::MCYCLEH:    source_data_out_new = mcycle[63:32];
        csr::MINSTRET:   source_data_out_new = minstret[31:0];
        csr::MINSTRETH:  source_data_out_new = minstret[63:32];
        default:         source_data_out_new = 32'b0;
    endcase
end

always_ff @(posedge clk) begin
    if (rst) begin
        source_data_out <= 32'b0;
    end
    else begin
        if (instruction_in.op inside {
                op::CSRRW,
                op::CSRRS,
                op::CSRRC,
                op::CSRRWI,
                op::CSRRSI,
                op::CSRRCI
            })
        begin
          /*  if(instruction_in.csr == csr::MCYCLE)
                source_data_out <= mcycle_curr;
            else if(instruction_in.csr == csr::MINSTRET)
               // source_data_out <= minstret_curr;
                source_data_out <= 0;
            else*/
            source_data_out <= source_data_out_new;
        end
    end
end


endmodule



/*verilator lint_on UNUSED*/
