class OSCSequenceTest < Oozey::Test
  test "window title" do
    session = parse("'abc' ", rows: 2, cols: 2)
    test = nil
    session.on_window_title do |title|
      test = title
    end

    parse("OSC 2 ; 'what is up?' bel", using: session)
    expect(test).to eql("what is up?")

    parse("OSC 0 ; 'hehe' esc \\", using: session)
    expect(test).to eql("hehe")
  end

  test "custom plugins" do
    session = parse("a b c", secret: "123");
    started = false
    plugin = nil
    data = []
    finished = false

    session.on_plugin do |command, id, *args|
      case command
      when :start
        started = true
        plugin = args[0]
      when :data
        data.concat args
      when :done
        finished = true
      when :cancel
      when :error
      end
    end

    parse("OSC '00z3;123;start;1;cool;beanns' bel", using: session)
    expect(started).to be(true)
    expect(finished).to be(false)
    expect(plugin).to eql("cool")
    expect(data).to eql([])

    parse("OSC '00z3;123;data;1;cool;YXdlc29tZQo=' bel", using: session)
    parse("OSC '00z3;123;data;1;cool;bW9yZQo=' bel", using: session)

    expect(data).to eql(["awesome\n", "more\n"])
    expect(finished).to be(false)

    parse("OSC '00z3;123;done;1' bel", using: session)
    expect(finished).to be(true)
  end

  test "custom plugins won't dispatch unless secrets match" do
    session = parse("a b c", secret: "245");
    received = false
    session.on_plugin do |command, id, *args|
      case command
      when :start then received = true
      when :data then received = true
      when :done then received = true
      when :cancel then received = true
      when :error then received = true
      end
    end
    
    parse("OSC '00z3;123;start;1;cool;beanns' bel", using: session)
    parse("OSC '00z3;123;data;1;cool;YXdlc29tZQo=' bel", using: session)
    parse("OSC '00z3;123;data;1;cool;bW9yZQo=' bel", using: session)
    parse("OSC '00z3;123;done;1' bel", using: session)


    expect(received).to be(false)
  end
end