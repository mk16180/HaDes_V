

/*verilator lint_off UNUSED*/



package trap_field;

    typedef struct packed {
        logic        valid;
        logic [31:0] epc;
        exception::excep_t excep_type;
    } tf;

endpackage : trap_field



/*verilator lint_on UNUSED*/