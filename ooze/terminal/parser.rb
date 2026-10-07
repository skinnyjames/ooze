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
      Action = Struct.new(:type, :codepoint, :intermediates, :params, :content, :private_marker) do
        def chr
          codepoint.chr
        end

        def private_marker_chr
          private_marker&.chr("UTF-8")
        end

        def intermediate_first
          intermediates[0]
        end

        def param_first
          params[0]
        end
      end

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

      def reset
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

      # Ignoring this range, because we don't support DEC Multinational, but everything above is printable unicode.
      C1_IGNORE_RANGE = (ASCII_MAX..ASCII_MAX | DEC_MN_CODE_TABLE[:apc])

      ANYWHERE = {
        SEQR["can"] => [:clear, :ground],
        SEQR["sub"] => [:clear, :ground],
        SEQR["esc"] => [:clear, :escape],
      }

      ON_ENTRY = { osc: :osc_start, escape: :clear, csi: :clear, dcs_passthrough: :hook }
      ON_EXIT = { osc: :osc_stop, dcs_passthrough: :unhook }

      # Transition table for the state machine
      # Hash of :state => { char_range => [:action, :new_state] }
      TRANSITIONS = {
        ground: {
          SEQR["nul .. us"] =>    [:execute, :ground],
          # Printable: not including delete (This terminal claims VT200 Compatible)
          SEQR["sp .. ~"] =>      [:print, :ground],
        },
        escape: {
          SEQR["nul .. us"] =>    [:execute, :escape],
          SEQR["sp .. /"] =>      [:collect, :escape_intermediate],
          SEQR["0 .. ~"] =>       [:escape_dispatch, :ground],
          SEQR["X"] =>            [:goto, :sos],
          SEQR["^"] =>            [:goto, :sos],
          SEQR["_"] =>            [:goto, :sos],
          SEQR["P"] =>            [:goto, :dcs],
          SEQR["]"] =>            [:goto, :osc],
          SEQR["["] =>            [:goto, :csi],
          SEQR["del"] =>          [:ignore, :escape],
        },
        escape_intermediate: {
          SEQR["nul .. us"] =>    [:execute, :escape_intermediate],
          SEQR["sp .. /"] =>      [:collect, :escape_intermediate],
          SEQR["0 .. ~"] =>       [:escape_dispatch, :ground],
          SEQR["del"] =>          [:ignore, :escape_intermediate],
        },
        osc: {
          SEQR["nul .. us"] =>    [:ignore, :osc],
          SEQR["sp .. del"] =>    [:osc_put, :osc],
          SEQR["bel"] =>          [:goto, :ground],
        },
        csi: {
          SEQR["nul .. us"] =>    [:execute, :csi],
          SEQR["del"] =>          [:ignore, :csi],
          SEQR["sp .. /"] =>      [:collect, :csi_intermediate],
          SEQR["0 .. ;"] =>       [:param, :csi_param],
          SEQR["< .. ?"] =>       [:collect, :csi_param],
          SEQR[":"] =>            [:goto, :csi_ignore],
          SEQR["@ .. ~"] =>       [:csi_dispatch, :ground],
        },
        csi_ignore: {
          SEQR["nul .. us"] =>    [:execute, :csi_ignore],
          SEQR["sp .. ?"] =>      [:ignore, :csi_ignore],
          SEQR["del"] =>          [:ignore, :csi_ignore],
          SEQR["@ .. ~"] =>       [:goto, :ground],
        },
        csi_param: {
          SEQR["nul .. us"] =>    [:execute, :csi_param],
          SEQR["0 .. 9"] =>       [:param, :csi_param],
          SEQR[": .. ?"] =>       [:goto, :csi_ignore],
          SEQR[";"] =>            [:param, :csi_param],
          SEQR["del"] =>          [:ignore, :csi_param],
          SEQR["sp .. /"] =>      [:collect, :csi_intermediate],
          SEQR["@ .. ~"] =>       [:csi_dispatch, :ground],
        },
        csi_intermediate: {
          SEQR["nul .. us"] =>    [:execute, :csi_intermediate],
          SEQR["sp .. /"] =>      [:collect, :csi_intermediate],
          SEQR["0 .. ?"] =>       [:goto, :csi_ignore],
          SEQR["@ .. ~"] =>       [:csi_dispatch, :ground],
          SEQR["del"] =>          [:ignore, :csi_intermediate],
        },
        dcs: {
          SEQR["nul .. us"] =>    [:ignore, :dcs],
          SEQR["sp .. /"] =>      [:collect, :dcs_intermediate],
          SEQR["0 .. ;"] =>       [:param, :dcs_param],
          SEQR["< .. ?"] =>       [:collect, :dcs_param],
          SEQR["@ .. ~"] =>       [:goto, :dcs_passthrough],
          SEQR[":"] =>            [:goto, :dcs_ignore],
          SEQR["del"] =>          [:ignore, :dcs],
        },
        dcs_ignore: {
          SEQR["nul .. del"] =>   [:ignore, :dcs_ignore],
        },
        dcs_param: {
          SEQR["nul .. us"] =>    [:ignore, :dcs_param],
          SEQR["0 .. ;"] =>       [:param, :dcs_param],
          SEQR[":"] =>            [:goto, :dcs_ignore],
          SEQR["< .. ?"] =>       [:goto, :dcs_ignore],
          SEQR["@ .. ~"] =>       [:goto, :dcs_passthrough],
          SEQR["sp .. /"] =>      [:collect, :dcs_intermediate],
          SEQR["del"] =>          [:ignore, :dcs_param],
        },
        dcs_intermediate: {
          SEQR["nul .. us"] =>    [:ignore, :dcs_intermediate],
          SEQR["sp .. /"] =>      [:collect, :dcs_intermediate],
          SEQR["del"] =>          [:ignore, :dcs_intermediate],
          SEQR["0 .. ?"] =>       [:goto, :dcs_ignore],
          SEQR["@ .. ~"] =>       [:goto, :dcs_passthrough],
        },
        dcs_passthrough: {
          SEQR["nul .. us"] =>    [:put, :dcs_passthrough],
          SEQR["sp .. ~"] =>      [:put, :dcs_passthrough],
          SEQR["del"] =>          [:ignore, :dcs_passthrough],
        },
        sos: {
          SEQR["nul .. del"] =>   [:ignore, :sos]
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
            handle_action(ON_ENTRY[new_state], codepoint) if ON_ENTRY[new_state]
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

