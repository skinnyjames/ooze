module Ooze
  module Terminal
    # Public: Parser for terminal escape sequences
    #         Based on prior art and implemented to support UTF-8
    #         https://github.com/coezbek/vtparser
    #         https://www.vt100.net/emu/dec_ansi_parser
    class Parser
      # Public: A Parser action
      #         yielded to the callback provided by 
      #         on_parse
      Action = Struct.new(:type, :codepoint, :intermediates, :params, :content, :private_marker)

      attr_reader :intermediates, :params, :state

      def initialize(session)
        @session = session
        @state = :ground
        @intermediates = []
        @params = []
        @printbuffer = ""
        @buffer = ""
        @ignore_flagged = false
        @on_parse = nil
      end

      def on_parse(&block)
        @on_parse = block
      end

      # Public: Turns a command into an ANSI Sequence for
      #         consumption by the pty
      #
      # command - Symbol or VTParser::Command
      #
      # Returns String
      def send_command(command)
        if command == VTParser::Command
          return command.to_s
        end

        COMMANDS[command]
      end

      # Ignoring this range, because we don't support DEC Multinational, but everything above is printable unicode.
      C1_IGNORE_RANGE = (ASCII_MAX..ASCII_MAX | DEC_MN_CODE_TABLE[:apc])

      ANYWHERE = {
        ASCII_CODE_TABLE[:can] => [:clear, :ground],
        ASCII_CODE_TABLE[:sub] => [:clear, :ground],
        ASCII_CODE_TABLE[:esc] => [:clear, :escape],
      }

      ON_GOTO = { osc: :osc_start, escape: :clear, csi: :clear, dcs_passthrough: :hook }
      ON_EXIT = { osc: :osc_stop, dcs_passthrough: :unhook }

      TRANSITIONS = {
        ground: {
          ASCII_CODE_TABLE[:nul]..ASCII_CODE_TABLE[:us] => [:execute, :ground],
          # Printable: not including delete (This terminal claims VT200 Compatible)
          (ASCII_CODE_TABLE[:sp]...ASCII_CODE_TABLE[:del]) => [:print, :ground],
        },
        escape: {
          (ASCII_CODE_TABLE[:nul]..ASCII_CODE_TABLE[:us]) => [:execute, :escape],
          (ASCII_CODE_TABLE[:sp]..ASCII_CODE_TABLE['/']) => [:collect, :escape_intermediate],
          (ASCII_CODE_TABLE['0']..ASCII_CODE_TABLE['~']) => [:escape_dispatch, :ground],
          ASCII_CODE_TABLE['X'] => [:goto, :sos],
          ASCII_CODE_TABLE['^'] => [:goto, :sos],
          ASCII_CODE_TABLE['_'] => [:goto, :sos],
          ASCII_CODE_TABLE['P'] => [:goto, :dcs],
          ASCII_CODE_TABLE[']'] => [:goto, :osc],
          ASCII_CODE_TABLE['['] => [:goto, :csi],
          ASCII_CODE_TABLE[:del] => [:ignore, :escape],
        },
        escape_intermediate: {
          (ASCII_CODE_TABLE[:nul]..ASCII_CODE_TABLE[:us]) => [:execute, :escape_intermediate],
          (ASCII_CODE_TABLE[:sp]..ASCII_CODE_TABLE['/']) => [:collect, :escape_intermediate],
          (ASCII_CODE_TABLE['0']..ASCII_CODE_TABLE['~']) => [:escape_dispatch, :ground],
          ASCII_CODE_TABLE[:del] => [:ignore, :escape_intermediate],
        },
        osc: {
          ASCII_CODE_TABLE[:nul]..ASCII_CODE_TABLE[:us] => [:ignore, :osc],
          ASCII_CODE_TABLE[:sp]..ASCII_CODE_TABLE[:del] => [:osc_put, :osc],
          ASCII_CODE_TABLE[:bel] => [:goto, :ground], # for xterm/modern terminals
        },
        csi: {
          ASCII_CODE_TABLE[:nul]..ASCII_CODE_TABLE[:us] => [:execute, :csi],
          ASCII_CODE_TABLE[:del] => [:ignore, :csi],
          ASCII_CODE_TABLE[:sp]..ASCII_CODE_TABLE['/'] => [:collect, :csi_intermediate],
          ASCII_CODE_TABLE['0']..ASCII_CODE_TABLE[';'] => [:param, :csi_param],
          ASCII_CODE_TABLE['<']..ASCII_CODE_TABLE['?'] => [:collect, :csi_param],
          ASCII_CODE_TABLE[':'] => [:goto, :csi_ignore],
          ASCII_CODE_TABLE['@']...ASCII_CODE_TABLE[:del] => [:csi_dispatch, :ground],
        },
        csi_ignore: {
          ASCII_CODE_TABLE[:nul]..ASCII_CODE_TABLE[:us] => [:execute, :csi_ignore],
          ASCII_CODE_TABLE[:sp]..ASCII_CODE_TABLE['?'] => [:ignore, :csi_ignore],
          ASCII_CODE_TABLE[:del] => [:ignore, :csi_ignore],
          ASCII_CODE_TABLE['@']...ASCII_CODE_TABLE[:del] => [:goto, :ground]
        },
        csi_param: {
          ASCII_CODE_TABLE[:nul]..ASCII_CODE_TABLE[:us] => [:execute, :csi_param],
          # 30 to 3B
          ASCII_CODE_TABLE['0']...ASCII_CODE_TABLE[':'] => [:param, :csi_param],
          ASCII_CODE_TABLE[':']..ASCII_CODE_TABLE['?'] => [:goto, :csi_ignore],
          ASCII_CODE_TABLE[';'] => [:param, :csi_param],
          ASCII_CODE_TABLE[:del] => [:ignore, :csi_param],
          ASCII_CODE_TABLE[:sp]..ASCII_CODE_TABLE['/'] => [:collect, :csi_intermediate],
          ASCII_CODE_TABLE['@']...ASCII_CODE_TABLE[:del] => [:csi_dispatch, :ground]
        },
        csi_intermediate: {
          ASCII_CODE_TABLE[:nul]..ASCII_CODE_TABLE[:us] => [:execute, :csi_intermediate],
          ASCII_CODE_TABLE[:sp]..ASCII_CODE_TABLE['/'] => [:collect, :csi_intermediate],
          ASCII_CODE_TABLE['0']..ASCII_CODE_TABLE['?'] => [:goto, :csi_ignore],
          ASCII_CODE_TABLE['@']...ASCII_CODE_TABLE[:del] => [:csi_dispatch, :ground],
          ASCII_CODE_TABLE[:del] => [:ignore, :csi_intermediate],
        },
        dcs: {
          (ASCII_CODE_TABLE[:nul]..ASCII_CODE_TABLE[:us]) => [:ignore, :dcs],
          ASCII_CODE_TABLE[:sp]..ASCII_CODE_TABLE['/'] => [:collect, :dcs_intermediate],
          ASCII_CODE_TABLE['0']..ASCII_CODE_TABLE[';'] => [:param, :dcs_param],
          ASCII_CODE_TABLE['<']..ASCII_CODE_TABLE['?'] => [:collect, :dcs_param],
          ASCII_CODE_TABLE['@']...ASCII_CODE_TABLE[:del] => [:goto, :dcs_passthrough],
          ASCII_CODE_TABLE[':'] => [:goto, :dcs_ignore],
          ASCII_CODE_TABLE[:del] => [:ignore, :dcs]
        },
        dcs_ignore: {
          ASCII_CODE_TABLE[:nul]..ASCII_CODE_TABLE[:del] => [:ignore, :dcs_ignore],      
        },
        dcs_param: {
          ASCII_CODE_TABLE[:nul]..ASCII_CODE_TABLE[:us] => [:ignore, :dcs_param],
          ASCII_CODE_TABLE['0']..ASCII_CODE_TABLE[';'] => [:param, :dcs_param],
          ASCII_CODE_TABLE[':'] => [:goto, :dcs_ignore],
          ASCII_CODE_TABLE['<']..ASCII_CODE_TABLE['?'] => [:goto, :dcs_ignore],
          ASCII_CODE_TABLE['@']..ASCII_CODE_TABLE['~'] => [:goto, :dcs_passthrough],
          ASCII_CODE_TABLE[:sp]..ASCII_CODE_TABLE['/'] => [:collect, :dcs_intermediate],
          ASCII_CODE_TABLE[:del] => [:ignore, :dcs_param]
        },
        dcs_intermediate: {
          ASCII_CODE_TABLE[:nul]..ASCII_CODE_TABLE[:us] => [:ignore, :dcs_intermediate],
          ASCII_CODE_TABLE[:sp]..ASCII_CODE_TABLE['/'] => [:collect, :dcs_intermediate],
          ASCII_CODE_TABLE[:del] => [:ignore, :dcs_intermediate],
          ASCII_CODE_TABLE['0']..ASCII_CODE_TABLE['?'] => [:goto, :dcs_ignore],
          ASCII_CODE_TABLE['@']..ASCII_CODE_TABLE['~'] => [:goto, :dcs_passthrough],
        },
        dcs_passthrough: {
          ASCII_CODE_TABLE[:nul]..ASCII_CODE_TABLE[:us] => [:put, :dcs_passthrough],
          ASCII_CODE_TABLE[:sp]..ASCII_CODE_TABLE['~'] => [:put, :dcs_passthrough],
          ASCII_CODE_TABLE[:del] => [:ignore, :dcs_passthrough]
        },
        sos: {
          ASCII_CODE_TABLE[:nul]..ASCII_CODE_TABLE[:del] => [:ignore, :sos]
        }
      }

      STATES = {}
      TRANSITIONS.each do |state, ranges|
        STATES[state] = Array.new(160, [:ignore, nil])
        
        ranges.each do |range, value|
          if range.is_a?(Range)
            range.to_a.each do |char|
              STATES[state][char] = value
            end
          else
            STATES[state][range] = value
          end
        end
        
        ANYWHERE.each do |key, val|
          STATES[state][key] = val
        end
      end

      # Public: Parses a string and invokes the callback for each action
      # 
      # string - the input string
      #
      # Returns nothing
      def parse(str)
        str.codepoints_each do |codepoint|
          # Outside ASCII range
          if codepoint >= 160
            case state
            when :ground
              handle_action(:print, codepoint)
            when :osc
              handle_action(:osc_put, codepoint)
            when :dcs_passthrough
              handle_action(:put, codepoint)
            end

            next
          end

          action, new_state = STATES[state][codepoint]
          new_state ||= state

          if state != new_state
            handle_action(ON_EXIT[state], codepoint) if ON_EXIT[state]
            handle_action(action, codepoint)
            handle_action(ON_GOTO[new_state], codepoint) if ON_GOTO[new_state]
          else
            handle_action(action, codepoint)
          end

          @state = new_state
        end
      end

      private

      def handle_action(action, codepoint)
        case action
        when :collect
          @private_marker ||= codepoint
          @intermediates << codepoint unless @ignore_flagged

          return
        when :param
          if codepoint == ASCII_CODE_TABLE[';']
            @params << 0 if @params.empty?
            @params << 0
            
            return
          end

          if @params.empty?
            @params << 0
          end

          @params[-1] = @params[-1] * 10 + (codepoint - ASCII_CODE_TABLE['0'])
        when :clear
          @private_marker = nil
          @buffer = ""
          @intermediates = []
          @params = []
          @ignore_flagged = false
        when :ignore, :goto
        else
          case action
          when :osc_start, :hook
            @buffer = ""
          when :osc_put, :put
            @buffer << codepoint.chr("UTF-8")

            return
          when :print
            @buffer = codepoint.chr("UTF-8")
          when :osc_stop, :unhook
            @buffer = ""
          end

          @on_parse&.call(Action.new(action, codepoint, @intermediates, @params, @buffer, @private_marker))

          return unless action == :csi_dispatch || action == :osc_dispatch || action == :escape_dispatch

          @buffer = ""
          @printbuffer = ""
          @private_marker = nil
          @intermediates = []
          @params = []
          @ignore_flagged = false
        end
      end
    end
  end
end

