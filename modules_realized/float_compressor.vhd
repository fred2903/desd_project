library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity float_compressor is
     generic(
         CHANNEL_LENGHT : positive := 24;
         OUTPUT_LENGHT  : positive := 16;
         EXPONENT_LENGTH : positive := 4
        -- MANTISSA_LENGTH : positive := 11 --OUTPUT_LENGTH - EXPONENT_LENGTH - 1 -- 16 - 4 - 1
 );
 port (
        aclk            : in std_logic;
        aresetn         : in std_logic;
        s_axis_tvalid   : in std_logic;
        s_axis_tdata    : in std_logic_vector(CHANNEL_LENGHT-1 downto 0);
        s_axis_tlast    : in std_logic;
        s_axis_tready   : out std_logic;
        m_axis_tvalid   : out std_logic;
        m_axis_tdata    : out std_logic_vector(OUTPUT_LENGHT-1 downto 0);
        m_axis_tlast    : out std_logic;
        m_axis_tready   : in std_logic
    );
end entity;

architecture rtl of float_compressor is

    type state_type is (IDLE, COMPRESS, SEND);
    signal state : state_type := IDLE;

    -- Registri interni per stabilità
    signal sample_reg    : std_logic_vector(CHANNEL_LENGHT-1 downto 0);
    signal tlast_reg     : std_logic;
    signal tlast_reg_out : std_logic;
    signal compressed_reg: std_logic_vector(OUTPUT_LENGHT-1 downto 0);
    
    -- Segnale combinatorio (la tua "sottofunzione")
    signal comb_out      : std_logic_vector(OUTPUT_LENGHT-1 downto 0);

begin
 -------------------------------------------------------------------------
    -- SOTTOFUNZIONE COMBINATORIA: Compressione all'interno del ciclo di compressione
    -------------------------------------------------------------------------
    process(sample_reg)
        variable MANTISSA_LENGTH : positive := OUTPUT_LENGHT - EXPONENT_LENGTH -1;
        variable sign               : std_logic;
        variable abs_value          : unsigned(CHANNEL_LENGHT-2 downto 0);
        variable first_one_pos      : integer range 0 to CHANNEL_LENGHT-2;
        variable exp                : unsigned(EXPONENT_LENGTH-1 downto 0);
        variable mantissa           : std_logic_vector(MANTISSA_LENGTH-1 downto 0);
        variable exp_temp           : integer;
    begin

        sign := sample_reg(CHANNEL_LENGHT-1);
        
        -- Modulo (Valore Assoluto)
        if sign = '1' then
            abs_value := unsigned(not sample_reg(CHANNEL_LENGHT-2 downto 0)) + 1;
        else
            abs_value := unsigned(sample_reg(CHANNEL_LENGHT-2 downto 0));
        end if;

        -- Leading One Detector 
        -- not really optimized, not scalable for higher bit widths, but it works for our fixed 24-bit input
        -- could consider to implement a tree of comparators for a more efficient solution in a real design
        first_one_pos := 0;
        for i in abs_value'high downto 0 loop
            if abs_value(i) = '1' then
                first_one_pos := i;
                exit;
            end if;
        end loop;

        -- Calcolo Esponente e Mantissa (Specifiche Lab)
        if first_one_pos < MANTISSA_LENGTH then
            exp  := (others => '0'); -- saturazione esponente a 0 
            mantissa := std_logic_vector(abs_value(MANTISSA_LENGTH-1 downto 0));
        else
            exp_temp := first_one_pos - MANTISSA_LENGTH + 1; -- Calcolo esponente temporaneo
            if(exp_temp > 2**EXPONENT_LENGTH - 1) then
                exp  := (others => '1'); -- Saturazione Esponente al massimo  
                mantissa := (others => '0'); -- Mantissa a zero in caso di overflow
            else

            exp  := to_unsigned(first_one_pos - MANTISSA_LENGTH + 1, EXPONENT_LENGTH);
            mantissa := std_logic_vector(abs_value(first_one_pos - 1 downto (first_one_pos - MANTISSA_LENGTH)));
        end if;
      end if;

        comb_out <= sign & std_logic_vector(exp) & mantissa;

    end process;

    -------------------------------------------------------------------------
    -- FSM SEQUENZIALE
    -------------------------------------------------------------------------
    
   with state select m_axis_tvalid <=

        '0' when IDLE,
        '0' when COMPRESS,
        '1' when SEND;

    with state select m_axis_tdata <=

        (others => '-') when IDLE,
        (others => '-') when COMPRESS,
        compressed_reg when SEND;

-- chiedere come fare per far si che quando sto compressando un dato A 
--e arriva un nuovo dato B, il sistema non si blocchi ma continui a comprimere A e ignori B,
-- oppure se è possibile mettere in una sorta di buffer B e comprimerlo subito dopo A

    with state select s_axis_tready <=
        
        '1' when IDLE,
        '0' when COMPRESS,
        '0' when SEND;

    with state select m_axis_tlast <=

        tlast_reg_out when SEND,
        '0' when others;


    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                state <= IDLE;
                tlast_reg <= '0';
            else
                case state is

                    when IDLE =>
                        if s_axis_tvalid = '1' then
                    -- Registriamo i dati in ingresso per stabilità
                            sample_reg <= s_axis_tdata;
                    -- Registriamo tlast per mantenerlo stabile durante la compressione
                            tlast_reg  <= s_axis_tlast;
                            state      <= COMPRESS;
                        end if;

                    when COMPRESS =>
                        -- Registriamo l'uscita combinatoria per spezzare il critical path
                        compressed_reg <= comb_out;
                        tlast_reg_out <= tlast_reg; -- Manteniamo stabile tlast durante l'invio
                        state <= SEND;

                    when SEND =>
                        if m_axis_tready = '1' then
                            state <= IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

end architecture;