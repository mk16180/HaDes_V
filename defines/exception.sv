package exception;

    typedef enum logic [4:0]{
        FETCH_MISALIGNED,
        FETCH_FAULT,
        ILLEGAL_INSTRUCTION,
        LOAD_MISALIGNED,
        LOAD_FAULT,
        STORE_MISALIGNED,
        STORE_FAULT,
        ECALL,
        EBREAK
    } excep_t;



endpackage : exception
