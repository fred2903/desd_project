library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity float_compressor is
    Generic (
        CHANNEL_LENGTH : positive := 24; -- 3 Byte for AXIS audio I2S
        OUTPUT_LENGTH : positive := 16; -- 2 Byte for float compression
        EXPONENT_LENGTH : positive := 4
    );
    Port (
        aclk : in std_logic;
        aresetn : in std_logic;

        s_axis_tvalid : in std_logic;
        s_axis_tdata : in std_logic_vector(CHANNEL_LENGTH-1 downto 0);
        s_axis_tlast : in std_logic;
        s_axis_tready : out std_logic;

        m_axis_tvalid : out std_logic;
        m_axis_tdata : out std_logic_vector(OUTPUT_LENGTH-1 downto 0);
        m_axis_tlast : out std_logic;
        m_axis_tready : in std_logic
    );
end entity float_compressor;

architecture rtl of float_compressor is

    ---------- CONSTANTS ----------
    constant MANTISSA_LENGTH : integer := OUTPUT_LENGTH - EXPONENT_LENGTH - 1;
    constant THRESHOLD : integer := 2**MANTISSA_LENGTH;
    -------------------------------

    ---------- TYPES ----------
    type state_type is (WAIT_DATA, COMPUTE_1, COMPUTE_2, SEND_DATA);
    ---------------------------

    ---------- SIGNALS ----------
    signal reg_data : std_logic_vector(CHANNEL_LENGTH-1 downto 0);
    signal reg_last : std_logic;
    signal state : state_type := WAIT_DATA;
    signal reg_sign : std_logic;
    signal reg_magnitude : unsigned(CHANNEL_LENGTH-1 downto 0);
    signal reg_leading_one_pos : integer range 0 to CHANNEL_LENGTH-1;
    signal compressed_data : std_logic_vector(OUTPUT_LENGTH-1 downto 0);
    -----------------------------

begin

    ---------- AXI4-STREAM OUTPUT FSM ----------
	with state select s_axis_tready <=
        '1' when WAIT_DATA,
        '0' when others;

    with state select m_axis_tvalid <=
        '1' when SEND_DATA,
        '0' when others;

    with state select m_axis_tdata <=
        compressed_data when SEND_DATA,
        (others => '-') when others;
        
    with state select m_axis_tlast <=
        reg_last when SEND_DATA,
        '0' when others;
	--------------------------------------------

    ---------- PROCESSES ----------
    process (aclk)
        variable sign_bit : std_logic;
        variable magnitude : unsigned(CHANNEL_LENGTH-1 downto 0);
        variable leading_one_pos : integer range 0 to CHANNEL_LENGTH-1;
        variable shifted_magnitude : unsigned(CHANNEL_LENGTH-1 downto 0);
        variable exp_val : unsigned(EXPONENT_LENGTH-1 downto 0);
        variable mant_val : unsigned(MANTISSA_LENGTH-1 downto 0);
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                state <= WAIT_DATA;
            else
                case state is

                    -- Wait for upstream tvalid high, then capture input data and move to COMPUTE_1 state
                    when WAIT_DATA =>
                        if s_axis_tvalid = '1' then
                            reg_data <= s_axis_tdata;
                            reg_last <= s_axis_tlast;
                            state <= COMPUTE_1;
                        end if;

                    -- Perform the compression algorithm to pass from a signed CHANNEL_LENGTH-bit input to a floating-point-like OUTPUT_LENGTH-bit output in the next two states (COMPUTE_1 and COMPUTE_2)
                    when COMPUTE_1 =>
                        -- Sign bit and two's complement absolute value extraction
                        sign_bit := reg_data(CHANNEL_LENGTH-1);
                        if sign_bit = '1' then -- Handles -0 non-existence automatically since -0 in two's complement is represented as all bits 0, which will be treated as +0
                            magnitude := unsigned(not(reg_data)) + 1;
                        else -- sign_bit = '0'
                            magnitude := unsigned(reg_data);
                        end if;

                        -- Locate the leading '1' in the magnitude starting from the LSB
                        leading_one_pos := 0;
                        for i in 0 to CHANNEL_LENGTH-1 loop
                            if magnitude(i) = '1' then
                                leading_one_pos := i; -- Last assignment wins, catching the highest index, i.e. the MSB
                            end if;
                        end loop;

                        -- Save intermediate results into pipeline registers for the next clock cycle processing
                        reg_sign <= sign_bit;
                        reg_magnitude <= magnitude;
                        reg_leading_one_pos <= leading_one_pos;

                        state <= COMPUTE_2;

                    when COMPUTE_2 =>
                        -- Mantissa and exponent calculation via magnitude bounds assessment
                        if reg_magnitude < THRESHOLD then
                            exp_val := to_unsigned(0, EXPONENT_LENGTH);
                            mant_val := reg_magnitude(MANTISSA_LENGTH-1 downto 0);
                        else
                            exp_val := to_unsigned(reg_leading_one_pos - MANTISSA_LENGTH + 1, EXPONENT_LENGTH);
                            -- Right shift to map variable mantissa bits to a static MANTISSA_LENGTH range
                            shifted_magnitude := shift_right(reg_magnitude, reg_leading_one_pos - MANTISSA_LENGTH);
                            mant_val := shifted_magnitude(MANTISSA_LENGTH-1 downto 0);
                        end if;

                        -- Compressed data vector packing
                        compressed_data(OUTPUT_LENGTH-1) <= reg_sign;
                        compressed_data((OUTPUT_LENGTH-2) downto MANTISSA_LENGTH) <= std_logic_vector(exp_val);
                        compressed_data((MANTISSA_LENGTH-1) downto 0) <= std_logic_vector(mant_val);

                        state <= SEND_DATA;

                    -- Wait for downstream tready high, then move back to WAIT_DATA state to process the next sample
                    when SEND_DATA =>
                        if m_axis_tready = '1' then
                            state <= WAIT_DATA;
                        end if;

                end case;
            end if;
        end if;
    end process;
    -------------------------------

end architecture;
