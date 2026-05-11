library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity float_compressor is
    generic(
        CHANNEL_LENGHT  : positive := 24;
        OUTPUT_LENGHT   : positive := 16;
        EXPONENT_LENGTH : positive := 4
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

    -- FSM States
    type state_type is (IDLE, SIG, LOD, COMPRESS, SEND);
    signal state : state_type := IDLE;

    -- Internal signals
    signal sample_reg         : std_logic_vector(CHANNEL_LENGHT-1 downto 0);
    signal sign_reg           : std_logic;
    signal abs_value_reg      : unsigned(CHANNEL_LENGHT-2 downto 0);
    signal first_one_pos_reg  : integer;
    signal tlast_reg     : std_logic;
    signal compressed_reg     : std_logic_vector(OUTPUT_LENGHT-1 downto 0);

begin

    -------------------------------------------------------------------------
    -- OUTPUT ASSIGNMENTS (AXIS HANDSHAKE)
    -------------------------------------------------------------------------
    with state select m_axis_tvalid <=

        '0' when IDLE,
        '0' when COMPRESS,
        '1' when SEND;

    with state select m_axis_tdata <=

        (others => '-') when IDLE,
        (others => '-') when COMPRESS,
        compressed_reg when SEND;

    with state select s_axis_tready <=
        
        '1' when IDLE,
        '0' when COMPRESS,
        '0' when SEND;

    with state select m_axis_tlast <=

        tlast_reg when SEND,
        '0' when others;

-------------------------------------------------------------------------
    -- FSM PROCESS 
    -------------------------------------------------------------------------
    process(aclk)
        -- variables to compute exponent and mantissa
        variable MANTISSA_LENGTH : integer := OUTPUT_LENGHT - EXPONENT_LENGTH - 1;
        variable exp_temp        : integer;
        variable exp_var         : unsigned(EXPONENT_LENGTH-1 downto 0);
        variable mantissa_var    : std_logic_vector(OUTPUT_LENGHT - EXPONENT_LENGTH - 2 downto 0);
        variable v_found         : boolean;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                state <= IDLE;
                sample_reg <= (others => '0');
                compressed_reg <= (others => '0');
                tlast_reg <= '0';
                first_one_pos_reg <= -1;
            else
                case state is

                    -- 1. IDLE PHASE: we receive the data and tlast, and we store them in registers for the next stages.
                    when IDLE =>
                        if s_axis_tvalid = '1' then
                            sample_reg <= s_axis_tdata;
                            tlast_reg <= s_axis_tlast; -- Salviamo il tlast una sola volta
                            state <= SIG;
                        end if;

                    -- 2. Instead of compressing the data in a single clock cycle, we break down the process into multiple stages to optimize timing.
                    -- sign and absolute value calculation are done in the first stage, then we can use the next clock cycle to find the position of the leading one, and finally we can calculate exponent and mantissa in the last stage. 
                    when SIG =>
                        sign_reg <= sample_reg(CHANNEL_LENGHT-1);
                        if sample_reg(CHANNEL_LENGHT-1) = '1' then
                            -- inversion 
                            abs_value_reg <= unsigned(not sample_reg(CHANNEL_LENGHT-2 downto 0)) + 1;
                        else
                            abs_value_reg <= unsigned(sample_reg(CHANNEL_LENGHT-2 downto 0));
                        end if;
                        state <= LOD;

                    -- 3. Leading One: we find the position of the first '1'. This will help us to calculate the exponent and mantissa
                    when LOD =>
                        v_found := false;
                        first_one_pos_reg <= -1; -- Default: in case we do not find any '1' (i.e., input is zero)
                        for i in abs_value_reg'high downto 0 loop
                            if abs_value_reg(i) = '1' then
                                first_one_pos_reg <= i;
                                v_found := true;
                                exit;
                            end if;
                        end loop;
                        state <= COMPRESS;

                    -- 4. Calculation of exponent and mantissa
                    when COMPRESS =>
                        if first_one_pos_reg = -1 then
                            -- if the input is zero, we set exponent and mantissa to zero
                            exp_var      := (others => '0');
                            mantissa_var := (others => '0');
                        elsif first_one_pos_reg < MANTISSA_LENGTH then
                            -- if we have less bits than the mantissa length, we shift the value to the left and set exponent to zero
                            exp_var      := (others => '0');
                            mantissa_var := std_logic_vector(resize(abs_value_reg, MANTISSA_LENGTH));
                        else
                            -- if the value of the exponent is greater than the maximum representable, we saturate the value to the maximum representable, otherwise we calculate the exponent and mantissa normally
                            -- e.g. 17, which is greater than the maximum representable with 4 bits (15), will be saturated to 15, while 14 will be represented as is.
                            exp_temp := first_one_pos_reg - MANTISSA_LENGTH + 1;
                            if exp_temp > (2**EXPONENT_LENGTH - 1) then
                                exp_var      := (others => '1'); -- saturation to max exponent
                                mantissa_var := (others => '0');
                            else
                            -- otherwise we calculate the exponent and mantissa normally
                                exp_var      := to_unsigned(exp_temp, EXPONENT_LENGTH);
                                mantissa_var := std_logic_vector(abs_value_reg(first_one_pos_reg-1 downto first_one_pos_reg - MANTISSA_LENGTH));
                            end if;
                        end if;

                        -- the final compressed value is the concatenation of the sign, exponent and mantissa
                        compressed_reg <= sign_reg & std_logic_vector(exp_var) & mantissa_var;
                        state <= SEND;

                    -- 5. SEND phase
                    when SEND =>
                        if m_axis_tready = '1' then
                            state <= IDLE;
                        end if;

                    when others =>
                        state <= IDLE;

                end case;
            end if;
        end if;
    end process;

end architecture;
