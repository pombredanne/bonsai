shared_examples_for 'a Bonsai implementation' do
  let(:header) { "" }
  subject { run_program :rules => rules, :start_state => start_state, :header => header }

  after do
    if subject[:compile_error]
      subject[:exit_status].should be_nil
      subject[:stdout].should be_nil
      subject[:stderr].should be_nil
      subject[:end_state].should be_nil
    else
      subject[:exit_status].should_not be_nil
      subject[:stdout].should_not be_nil
      subject[:stderr].should_not be_nil
      subject[:end_state].should_not be_nil if subject[:exit_status] == 1
      subject[:end_state].should     be_nil if subject[:exit_status] != 1
    end
  end

  def self.it_applies_the_rule end_state
    it 'applies the rule' do
      subject[:end_state].should == parse_state(end_state)
    end
  end

  def self.it_does_not_apply_the_rule
    it 'does not apply the rule' do
      subject[:end_state].should == parse_state(start_state)
    end
  end

  def self.it_causes_a_compile_error
    it 'causes a compile error' do
      subject[:compile_error].should be_true
    end
  end

  def self.it_allows_the_variable_to_be_used_in_a_code_segment variable, type
    describe 'used in a code segment' do
      before do
        depth = rules.match(/^ */)[0]
        @assignments[:rules] += "#{depth}< printf(\"%s\", $#{variable}->type);"
      end
      it 'binds the variable' do
        subject[:stdout].should == type
      end
    end
  end

  def self.it_does_not_allow_the_variable_to_be_used_in_a_code_segment variable
    describe 'used in a code segment' do
      let(:start_state) { "Unmatched:" }
      before do
        depth = rules.match(/^ */)[0]
        @assignments[:rules] += "#{depth}< printf(\"%s\", $#{variable}->type);"
      end
      it_causes_a_compile_error
    end
  end

  def parse_state definition
    nodes = definition.split "\n"
    state = []

    return state if nodes.empty?
    depth = nodes.first.match(/^ */)[0].length

    parent = nodes.shift
    children = []
    nodes.each do |node|
      if node.match /^ {#{depth}}[^ ]/
        state += [{:label => parent.sub(/^ {#{depth}}/, ''), :children => parse_state(children.join "\n")}]
        parent = node
        children = []
      else
        children += [node]
      end
    end
    state + [{:label => parent.sub(/^ {#{depth}}/, ''), :children => parse_state(children.join "\n")}]
  end

  describe 'halting' do
    let(:rules) { "Foo:" }

    describe 'when no rules match' do
      let(:start_state) { "Bar:" }
      it 'errors out' do
        subject[:exit_status].should == 1
        subject[:stdout].should == ""
        subject[:stderr].should == "No rules to apply!\n#{start_state}\n"
        subject[:end_state].should == parse_state(start_state)
      end
    end

    describe 'when no rules make a change' do
      let(:start_state) { "Foo:" }
      it 'errors out' do
        subject[:exit_status].should == 1
        subject[:stdout].should == ""
        subject[:stderr].should == "No rules to apply!\n#{start_state}\n"
        subject[:end_state].should == parse_state(start_state)
      end
    end
  end

  describe 'executing code' do
    let(:start_state) { "Foo:" }

    describe 'of a matched rule' do
      let(:rules) { "Foo:\n< exit(0);" }
      it 'executes the code' do
        subject[:exit_status].should == 0
        subject[:stdout].should == ""
        subject[:stderr].should == ""
      end

      describe 'with multiple lines of code' do
        let(:rules) { "Foo:\n< printf(\"bar\");\n< exit(0);" }
        it 'executes the code' do
          subject[:exit_status].should == 0
          subject[:stdout].should == "bar"
          subject[:stderr].should == ""
        end
      end
    end

    describe 'of an unmatched rule' do
      let(:rules) { "Bar:\n< exit(0);" }
      it 'does not execute the code' do
        subject[:exit_status].should == 1
        subject[:stdout].should == ""
        subject[:stderr].should == "No rules to apply!\n#{start_state}\n"
        subject[:end_state].should == parse_state(start_state)
      end
    end

    describe 'that is invalid' do
      let(:rules) { "Bar:\n< not_valid_code;" }
      it_causes_a_compile_error
    end
  end

  describe 'header' do
    let(:header) { <<-EOS }
      %{
        void f() {
          #{code}
        }
      %}
    EOS
    let(:rules) { "Foo:\n< f();" }
    let(:start_state) { "Foo:" }

    describe 'with valid code' do
      let(:code) { "exit(0);" }
      it 'exectutes the code' do
        subject[:exit_status].should == 0
        subject[:stdout].should == ""
        subject[:stderr].should == ""
      end
    end

    describe 'with invalid code' do
      let(:code) { "not_valid_code;" }
      it_causes_a_compile_error
    end
  end

  describe 'root label' do
    let(:rules) { <<-EOS }
      ^:
        Foo:
      < exit(0);
    EOS

    describe 'when conditions match at the root level' do
      let(:start_state) { <<-EOS }
        Bar:
        Foo:
        Baz:
      EOS

      it 'applies the rule' do
        subject[:exit_status].should == 0
      end
    end

    describe 'when the conditions match below the root level' do
      let(:start_state) { <<-EOS }
        Bar:
          Foo:
        Baz:
      EOS

      it_does_not_apply_the_rule
    end
  end

  describe 'creating nodes' do
    describe 'at the root level' do
      let(:rules) { <<-EOS }
        Foo:
        < exit(0);

        +Foo:
      EOS
      let(:start_state) { "" }

      it 'creates the node' do
        subject[:exit_status].should == 0
      end
    end

    describe 'in a child condition' do
      let(:rules) { <<-EOS }
        Foo:
        < exit(0);

        Bar:
          +Foo:
      EOS

      describe 'with a matching parent' do
        let(:start_state) { "Bar:" }

        it 'creates the node' do
          subject[:exit_status].should == 0
        end
      end

      describe 'without a matching parent' do
        let(:start_state) { "Baz:" }
        it_does_not_apply_the_rule
      end
    end

    describe 'with children' do
      let(:rules) { <<-EOS }
        Foo:
        < exit(0);

        +Bar:
          Foo:
      EOS

      it 'creates the children' do
        subject[:exit_status].should == 0
      end
    end
  end

  describe 'removing nodes' do
    describe 'at the root level' do
      let(:rules) { "-Foo:" }
      let(:start_state) { "Foo:" }
      it_applies_the_rule ""
    end

    describe 'in a child condition' do
      let(:rules) { "Foo:\n  -Bar:" }
      let(:start_state) { "Foo:\n  Bar:" }
      it_applies_the_rule "Foo:"
    end

    describe 'with children' do
      let(:rules) { "-Foo:\n  Bar:" }

      describe 'that match' do
        let(:start_state) { "Foo:\n  Bar:" }
        it_applies_the_rule ""
      end

      describe 'that do not match' do
        let(:start_state) { "Foo:\n  Baz:" }
        it_does_not_apply_the_rule
      end
    end
  end

  describe 'preventing a match' do
    let(:rules) { "!Foo:\n-Bar:" }

    describe 'when a match-preventing condition does not match' do
      let(:start_state) { "Bar:\nBaz:" }
      it_applies_the_rule "Baz:"
    end

    describe 'when a match-preventing condition matches' do
      let(:start_state) { "Bar:\nFoo:" }
      it_does_not_apply_the_rule
    end
  end

  describe 'unordered child conditions' do
    let(:rules) { <<-EOS }
      Foo:
        Bar:
        Baz:
      < exit(0);
    EOS

    describe 'matching unordered child nodes' do
      describe 'that match in order' do
        let(:start_state) { <<-EOS }
          Foo:
            Bar:
            Baz:
        EOS

        it 'applies the rule' do
          subject[:exit_status].should == 0
        end
      end

      describe 'that match out of order' do
        let(:start_state) { <<-EOS }
          Foo:
            Baz:
            Bar:
        EOS

        it 'applies the rule' do
          subject[:exit_status].should == 0
        end
      end
    end

    describe 'matching ordered child nodes' do
      describe 'that match in order' do
        let(:start_state) { <<-EOS }
          Foo::
            Bar:
            Baz:
        EOS

        it 'applies the rule' do
          subject[:exit_status].should == 0
        end
      end

      describe 'that match out of order' do
        let(:start_state) { <<-EOS }
          Foo::
            Baz:
            Bar:
        EOS

        it 'applies the rule' do
          subject[:exit_status].should == 0
        end
      end
    end
  end

  describe 'ordered child conditions' do
    let(:rules) { <<-EOS }
      Foo::
        Bar:
        Baz:
      < exit(0);
    EOS

    describe 'matching unordered child nodes' do
      describe 'that match in order' do
        let(:start_state) { <<-EOS }
          Foo:
            Bar:
            Baz:
        EOS
        it_does_not_apply_the_rule
      end

      describe 'that match out of order' do
        let(:start_state) { <<-EOS }
          Foo:
            Baz:
            Bar:
        EOS
        it_does_not_apply_the_rule
      end
    end

    describe 'matching ordered child nodes' do
      describe 'that match in order' do
        describe 'from the beginning' do
          let(:start_state) { <<-EOS }
            Foo::
              Bar:
              Baz:
          EOS

          it 'applies the rule' do
            subject[:exit_status].should == 0
          end
        end

        describe 'from the middle' do
          let(:start_state) { <<-EOS }
            Foo::
              Qux:
              Bar:
              Baz:
          EOS
          it_does_not_apply_the_rule
        end
      end

      describe 'that match out of order' do
        let(:start_state) { <<-EOS }
          Foo::
            Baz:
            Bar:
        EOS
        it_does_not_apply_the_rule
      end
    end
  end

  describe 'matching multiple nodes' do
    let(:rules) { <<-EOS }
      -Foo:
      -Bar:*
    EOS

    describe 'with no nodes that match' do
      let(:start_state) { "Foo:" }
      it_applies_the_rule ""
    end

    describe 'with one node that matches' do
      let(:start_state) { "Foo:\nBar:" }
      it_applies_the_rule ""
    end

    describe 'with multiple nodes that match' do
      let(:start_state) { "Foo:\nBar:\nBar:" }
      it_applies_the_rule ""
    end
  end

  describe 'not matching all nodes with a condition' do
    let(:rules) { <<-EOS }
      Foo:
        Bar:
        Baz:
      < exit(0);
    EOS

    describe 'with all child nodes matching' do
      let(:start_state) { <<-EOS }
        Foo:
          Bar:
          Baz:
      EOS

      it 'applies the rule' do
        subject[:exit_status].should == 0
      end
    end

    describe 'with some child nodes not matching' do
      let(:start_state) { <<-EOS }
        Foo:
          Bar:
          Baz:
          Qux:
      EOS

      it 'applies the rule' do
        subject[:exit_status].should == 0
      end
    end
  end

  describe 'matching all nodes with a condition' do
    let(:rules) { <<-EOS }
      Foo:=
        Bar:
        Baz:
      < exit(0);
    EOS

    describe 'with all child nodes matching' do
      let(:start_state) { <<-EOS }
        Foo:
          Bar:
          Baz:
      EOS

      it 'applies the rule' do
        subject[:exit_status].should == 0
      end
    end

    describe 'with some child nodes not matching' do
      let(:start_state) { <<-EOS }
        Foo:
          Bar:
          Baz:
          Qux:
      EOS
      it_does_not_apply_the_rule
    end
  end

  describe 'node values' do
    # TODO
  end

  describe 'variables' do
    describe 'referenced in a matching condition' do
      let(:rules) { <<-EOS }
        Matching: X
        !Matched:
        +Matched:
      EOS

      describe 'matching a leaf node' do
        let(:start_state) { "Matching:" }
        it_applies_the_rule "Matching:\nMatched:"
        it_allows_the_variable_to_be_used_in_a_code_segment "X", "Matching"
      end

      describe 'matching a node with children' do
        let(:start_state) { "Matching:\n  Child:" }
        it_applies_the_rule "Matching:\n  Child:\nMatched:"
        it_allows_the_variable_to_be_used_in_a_code_segment "X", "Matching"
      end

      describe 'matching a node with a value' do
        let(:start_state) { "Matching: 4" }
        it_applies_the_rule "Matching: 4\nMatched:"
        it_allows_the_variable_to_be_used_in_a_code_segment "X", "Matching"
      end

      describe 'and another matching condition' do
        let(:rules) { <<-EOS }
          Matching 1: X
          Matching 2: X
          !Matched:
          +Matched:
        EOS

        it_does_not_allow_the_variable_to_be_used_in_a_code_segment "X"

        describe 'matching a leaf node' do
          describe 'and a leaf node' do
            let(:start_state) { "Matching 1:\nMatching 2:" }
            it_applies_the_rule "Matching 1:\nMatching 2:\nMatched:"
          end

          describe 'and a node with children' do
            let(:start_state) { "Matching 1:\nMatching 2:\n  Child:" }
            it_does_not_apply_the_rule
          end

          describe 'and a node with a value' do
            let(:start_state) { "Matching 1:\nMatching 2: 5" }
            it_does_not_apply_the_rule
          end
        end

        describe 'matching a node with children' do
          describe 'and a node with children' do
            # TODO
          end

          describe 'and a node with a value' do
            let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5" }
            it_does_not_apply_the_rule
          end
        end

        describe 'matching a node with a value' do
          describe 'and a node with a value' do
            describe 'that are equal integers' do
              let(:start_state) { "Matching 1: 5\nMatching 2: 5" }
              it_applies_the_rule "Matching 1: 5\nMatching 2: 5\nMatched:"
            end

            describe 'that are unequal integers' do
              let(:start_state) { "Matching 1: 4\nMatching 2: 5" }
              it_does_not_apply_the_rule
            end

            describe 'that are equal decimals' do
              let(:start_state) { "Matching 1: 5.0\nMatching 2: 5.0" }
              it_applies_the_rule "Matching 1: 5.0\nMatching 2: 5.0\nMatched:"
            end

            describe 'that are unequal decimals' do
              let(:start_state) { "Matching 1: 4.0\nMatching 2: 5.0" }
              it_does_not_apply_the_rule
            end

            describe 'that are an integer and a decimal' do
              let(:start_state) { "Matching 1: 5\nMatching 2: 5.0" }
              it_does_not_apply_the_rule
            end
          end
        end

        describe 'and a removing condition' do
          let(:rules) { <<-EOS }
            Matching 1: X
            Matching 2: X
            -Removing: X
          EOS

          it_does_not_allow_the_variable_to_be_used_in_a_code_segment "X"

          describe 'matching a leaf node' do
            describe 'and a leaf node' do
              describe 'and a leaf node' do
                let(:start_state) { "Matching 1:\nMatching 2:\nRemoving:" }
                it_applies_the_rule "Matching 1:\nMatching 2:"
              end

              describe 'and a node with children' do
                let(:start_state) { "Matching 1:\nMatching 2:\nRemoving:\n  Child:" }
                it_does_not_apply_the_rule
              end

              describe 'and a node with a value' do
                let(:start_state) { "Matching 1:\nMatching 2:\nRemoving: 5" }
                it_does_not_apply_the_rule
              end
            end

            describe 'and a node with children' do
              describe 'and a leaf node' do
                let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving:" }
                it_does_not_apply_the_rule
              end

              describe 'and a node with children' do
                let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving:\n  Child:" }
                it_does_not_apply_the_rule
              end

              describe 'and a node with a value' do
                let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving: 5" }
                it_does_not_apply_the_rule
              end
            end

            describe 'and a node with a value' do
              describe 'and a leaf node' do
                let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving:" }
                it_does_not_apply_the_rule
              end

              describe 'and a node with children' do
                let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving:\n  Child:" }
                it_does_not_apply_the_rule
              end

              describe 'and a node with a value' do
                let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving: 5" }
                it_does_not_apply_the_rule
              end
            end
          end

          describe 'matching a node with children' do
            describe 'and a node with children' do
              describe 'and a leaf node' do
                let(:start_state) { "Matching 1:\n  Child:\nMatching 2:\n  Child:\nRemoving:" }
                it_does_not_apply_the_rule
              end

              describe 'and a node with children' do
                # TODO
              end

              describe 'and a node with a value' do
                let(:start_state) { "Matching 1:\n  Child:\nMatching 2:\n  Child:\nRemoving: 5" }
                it_does_not_apply_the_rule
              end
            end

            describe 'and a node with a value' do
              describe 'and a leaf node' do
                let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving:" }
                it_does_not_apply_the_rule
              end

              describe 'and a node with children' do
                let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving:\n  Child:" }
                it_does_not_apply_the_rule
              end

              describe 'and a node with a value' do
                let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving: 5" }
                it_does_not_apply_the_rule
              end
            end
          end

          describe 'matching a node with a value' do
            describe 'and a node with a value' do
              describe 'and a leaf node' do
                let(:start_state) { "Matching 1: 5\nMatching 2: 5\nRemoving:" }
                it_does_not_apply_the_rule
              end

              describe 'and a node with children' do
                let(:start_state) { "Matching 1: 5\nMatching 2: 5\nRemoving:\n  Child:" }
                it_does_not_apply_the_rule
              end

              describe 'and a node with a value' do
                describe 'that are equal integers' do
                  let(:start_state) { "Matching 1: 5\nMatching 2: 5\nRemoving: 5" }
                  it_applies_the_rule "Matching 1: 5\nMatching 2: 5"
                end

                describe 'that are unequal integers' do
                  let(:start_state) { "Matching 1: 5\nMatching 2: 4\nRemoving: 5" }
                  it_does_not_apply_the_rule
                end

                describe 'that are equal decimals' do
                  let(:start_state) { "Matching 1: 5.3\nMatching 2: 5.3\nRemoving: 5.3" }
                  it_applies_the_rule "Matching 1: 5.3\nMatching 2: 5.3"
                end

                describe 'that are unequal decimals' do
                  let(:start_state) { "Matching 1: 5.3\nMatching 2: 4.3\nRemoving: 5.3" }
                  it_does_not_apply_the_rule
                end

                describe 'that are integers and decimals' do
                  let(:start_state) { "Matching 1: 5.0\nMatching 2: 5\nRemoving: 5.0" }
                  it_does_not_apply_the_rule
                end
              end
            end
          end

          describe 'and a creating condition' do
            let(:rules) { <<-EOS }
              Matching 1: X
              Matching 2: X
              -Removing: X
              +Creating: X
            EOS

            it_does_not_allow_the_variable_to_be_used_in_a_code_segment "X"

            describe 'matching a leaf node' do
              describe 'and a leaf node' do
                describe 'and a leaf node' do
                  let(:start_state) { "Matching 1:\nMatching 2:\nRemoving:" }
                  it_applies_the_rule "Matching 1:\nMatching 2:\nCreating:"
                end

                describe 'and a node with children' do
                  let(:start_state) { "Matching 1:\nMatching 2:\nRemoving:\n  Child:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with a value' do
                  let(:start_state) { "Matching 1:\nMatching 2:\nRemoving: 5" }
                  it_does_not_apply_the_rule
                end
              end

              describe 'and a node with children' do
                describe 'and a leaf node' do
                  let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with children' do
                  let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving:\n  Child:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with a value' do
                  let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving: 5" }
                  it_does_not_apply_the_rule
                end
              end

              describe 'and a node with a value' do
                describe 'and a leaf node' do
                  let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with children' do
                  let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving:\n  Child:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with a value' do
                  let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving: 5" }
                  it_does_not_apply_the_rule
                end
              end
            end

            describe 'matching a node with children' do
              describe 'and a node with children' do
                describe 'and a leaf node' do
                  let(:start_state) { "Matching 1:\n  Child:\nMatching 2:\n  Child:\nRemoving:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with children' do
                  # TODO
                end

                describe 'and a node with a value' do
                  let(:start_state) { "Matching 1:\n  Child:\nMatching 2:\n  Child:\nRemoving: 5" }
                  it_does_not_apply_the_rule
                end
              end

              describe 'and a node with a value' do
                describe 'and a leaf node' do
                  let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with children' do
                  let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving:\n  Child:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with a value' do
                  let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving: 5" }
                  it_does_not_apply_the_rule
                end
              end
            end

            describe 'matching a node with a value' do
              describe 'and a node with a value' do
                describe 'and a leaf node' do
                  let(:start_state) { "Matching 1: 5\nMatching 2: 5\nRemoving:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with children' do
                  let(:start_state) { "Matching 1: 5\nMatching 2: 5\nRemoving:\n  Child:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with a value' do
                  describe 'that are equal integers' do
                    let(:start_state) { "Matching 1: 5\nMatching 2: 5\nRemoving: 5" }
                    it_applies_the_rule "Matching 1: 5\nMatching 2: 5\nCreating: 5"
                  end

                  describe 'that are unequal integers' do
                    let(:start_state) { "Matching 1: 5\nMatching 2: 4\nRemoving: 5" }
                    it_does_not_apply_the_rule
                  end

                  describe 'that are equal decimals' do
                    let(:start_state) { "Matching 1: 5.3\nMatching 2: 5.3\nRemoving: 5.3" }
                    it_applies_the_rule "Matching 1: 5.3\nMatching 2: 5.3\nCreating: 5.3"
                  end

                  describe 'that are unequal decimals' do
                    let(:start_state) { "Matching 1: 5.3\nMatching 2: 4.3\nRemoving: 5.3" }
                    it_does_not_apply_the_rule
                  end

                  describe 'that are integers and decimals' do
                    let(:start_state) { "Matching 1: 5.0\nMatching 2: 5\nRemoving: 5.0" }
                    it_does_not_apply_the_rule
                  end
                end
              end
            end

            describe 'and a preventing condition' do
              let(:rules) { <<-EOS }
                Matching 1: X
                Matching 2: X
                -Removing: X
                +Creating: X
                !Preventing: X
              EOS

              it_does_not_allow_the_variable_to_be_used_in_a_code_segment "X"

              describe 'matching a leaf node' do
                describe 'and a leaf node' do
                  describe 'and a leaf node' do
                    describe 'and a leaf node' do
                      let(:start_state) { "Matching 1:\nMatching 2:\nRemoving:\nPreventing:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with children' do
                      let(:start_state) { "Matching 1:\nMatching 2:\nRemoving:\nPreventing:\n  Child:" }
                      it_applies_the_rule "Matching 1:\nMatching 2:\nCreating:\nPreventing:\n  Child:"
                    end

                    describe 'and a node with a value' do
                      let(:start_state) { "Matching 1:\nMatching 2:\nRemoving:\nPreventing: 5" }
                      it_applies_the_rule "Matching 1:\nMatching 2:\nCreating:\nPreventing: 5"
                    end
                  end

                  describe 'and a node with children' do
                    describe 'and a leaf node' do
                      let(:start_state) { "Matching 1:\nMatching 2:\nRemoving:\n  Child:\nPreventing:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with children' do
                      let(:start_state) { "Matching 1:\nMatching 2:\nRemoving:\n  Child:\nPreventing:\n  Child:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with a value' do
                      let(:start_state) { "Matching 1:\nMatching 2:\nRemoving:\n  Child:\nPreventing: 5" }
                      it_does_not_apply_the_rule
                    end
                  end

                  describe 'and a node with a value' do
                    describe 'and a leaf node' do
                      let(:start_state) { "Matching 1:\nMatching 2:\nRemoving: 5\nPreventing:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with children' do
                      let(:start_state) { "Matching 1:\nMatching 2:\nRemoving: 5\nPreventing:\n  Child:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with a value' do
                      let(:start_state) { "Matching 1:\nMatching 2:\nRemoving: 5\nPreventing: 5" }
                      it_does_not_apply_the_rule
                    end
                  end
                end

                describe 'and a node with children' do
                  describe 'and a leaf node' do
                    describe 'and a leaf node' do
                      let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving:\nPreventing:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with children' do
                      let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving:\nPreventing:\n  Child:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with a value' do
                      let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving:\nPreventing: 5" }
                      it_does_not_apply_the_rule
                    end
                  end

                  describe 'and a node with children' do
                    describe 'and a leaf node' do
                      let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving:\n  Child:\nPreventing:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with children' do
                      let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving:\n  Child:\nPreventing:\n  Child:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with a value' do
                      let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving:\n  Child:\nPreventing: 5" }
                      it_does_not_apply_the_rule
                    end
                  end

                  describe 'and a node with a value' do
                    describe 'and a leaf node' do
                      let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving: 5\nPreventing:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with children' do
                      let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving: 5\nPreventing:\n  Child:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with a value' do
                      let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving: 5\nPreventing: 5" }
                      it_does_not_apply_the_rule
                    end
                  end
                end

                describe 'and a node with a value' do
                  describe 'and a leaf node' do
                    describe 'and a leaf node' do
                      let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving:\nPreventing:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with children' do
                      let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving:\nPreventing:\n  Child:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with a value' do
                      let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving:\nPreventing: 5" }
                      it_does_not_apply_the_rule
                    end
                  end

                  describe 'and a node with children' do
                    describe 'and a leaf node' do
                      let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving:\n  Child:\nPreventing:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with children' do
                      let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving:\n  Child:\nPreventing:\n  Child:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with a value' do
                      let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving:\n  Child:\nPreventing: 5" }
                      it_does_not_apply_the_rule
                    end
                  end

                  describe 'and a node with a value' do
                    describe 'and a leaf node' do
                      let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving: 5\nPreventing:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with children' do
                      let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving: 5\nPreventing:\n  Child:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with a value' do
                      let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving: 5\nPreventing: 5" }
                      it_does_not_apply_the_rule
                    end
                  end
                end
              end

              describe 'matching a node with children' do
                describe 'and a node with children' do
                  describe 'and a leaf node' do
                    describe 'and a leaf node' do
                      let(:start_state) { "Matching 1:\n  Child:\nMatching 2:\n  Child:\nRemoving:\nPreventing:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with children' do
                      let(:start_state) { "Matching 1:\n  Child:\nMatching 2:\n  Child:\nRemoving:\nPreventing:\n  Child:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with a value' do
                      let(:start_state) { "Matching 1:\n  Child:\nMatching 2:\n  Child:\nRemoving:\nPreventing: 5" }
                      it_does_not_apply_the_rule
                    end
                  end

                  describe 'and a node with children' do
                    describe 'and a leaf node' do
                      # TODO
                    end

                    describe 'and a node with children' do
                      # TODO
                    end

                    describe 'and a node with a value' do
                      # TODO
                    end
                  end

                  describe 'and a node with a value' do
                    describe 'and a leaf node' do
                      let(:start_state) { "Matching 1:\n  Child:\nMatching 2:\n  Child:\nRemoving: 5\nPreventing:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with children' do
                      let(:start_state) { "Matching 1:\n  Child:\nMatching 2:\n  Child:\nRemoving: 5\nPreventing:\n  Child:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with a value' do
                      let(:start_state) { "Matching 1:\n  Child:\nMatching 2:\n  Child:\nRemoving: 5\nPreventing: 5" }
                      it_does_not_apply_the_rule
                    end
                  end
                end

                describe 'and a node with a value' do
                  describe 'and a leaf node' do
                    describe 'and a leaf node' do
                      let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving:\nPreventing:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with children' do
                      let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving:\nPreventing:\n  Child:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with a value' do
                      let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving:\nPreventing: 5" }
                      it_does_not_apply_the_rule
                    end
                  end

                  describe 'and a node with children' do
                    describe 'and a leaf node' do
                      let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving:\n  Child:\nPreventing:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with children' do
                      let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving:\n  Child:\nPreventing:\n  Child:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with a value' do
                      let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving:\n  Child:\nPreventing: 5" }
                      it_does_not_apply_the_rule
                    end
                  end

                  describe 'and a node with a value' do
                    describe 'and a leaf node' do
                      let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving: 5\nPreventing:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with children' do
                      let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving: 5\nPreventing:\n  Child:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with a value' do
                      let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving: 5\nPreventing: 5" }
                      it_does_not_apply_the_rule
                    end
                  end
                end
              end

              describe 'matching a node with a value' do
                describe 'and a node with a value' do
                  describe 'and a leaf node' do
                    describe 'and a leaf node' do
                      let(:start_state) { "Matching 1: 5\nMatching 2: 5\nRemoving:\nPreventing:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with children' do
                      let(:start_state) { "Matching 1: 5\nMatching 2: 5\nRemoving:\nPreventing:\n  Child:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with a value' do
                      let(:start_state) { "Matching 1: 5\nMatching 2: 5\nRemoving:\nPreventing: 5" }
                      it_does_not_apply_the_rule
                    end
                  end

                  describe 'and a node with children' do
                    describe 'and a leaf node' do
                      let(:start_state) { "Matching 1: 5\nMatching 2: 5\nRemoving:\n  Child:\nPreventing:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with children' do
                      let(:start_state) { "Matching 1: 5\nMatching 2: 5\nRemoving:\n  Child:\nPreventing:\n  Child:" }
                      it_does_not_apply_the_rule
                    end

                    describe 'and a node with a value' do
                      let(:start_state) { "Matching 1: 5\nMatching 2: 5\nRemoving:\n  Child:\nPreventing: 5" }
                      it_does_not_apply_the_rule
                    end
                  end

                  describe 'and a node with a value' do
                    describe 'and a leaf node' do
                      # TODO
                    end

                    describe 'and a node with children' do
                      # TODO
                    end

                    describe 'and a node with a value' do
                      # TODO
                    end
                  end
                end
              end
            end
          end

          describe 'and a preventing condition' do
            let(:rules) { <<-EOS }
              Matching 1: X
              Matching 2: X
              -Removing: X
              !Preventing: X
            EOS

            it_does_not_allow_the_variable_to_be_used_in_a_code_segment "X"

            describe 'matching a leaf node' do
              describe 'and a leaf node' do
                describe 'and a leaf node' do
                  describe 'and a leaf node' do
                    let(:start_state) { "Matching 1:\nMatching 2:\nRemoving:\nPreventing:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with children' do
                    let(:start_state) { "Matching 1:\nMatching 2:\nRemoving:\nPreventing:\n  Child:" }
                    it_applies_the_rule "Matching 1:\nMatching 2:\nPreventing:\n  Child:"
                  end

                  describe 'and a node with a value' do
                    let(:start_state) { "Matching 1:\nMatching 2:\nRemoving:\nPreventing: 5" }
                    it_applies_the_rule "Matching 1:\nMatching 2:\nPreventing: 5"
                  end
                end

                describe 'and a node with children' do
                  describe 'and a leaf node' do
                    let(:start_state) { "Matching 1:\nMatching 2:\nRemoving:\n  Child:\nPreventing:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with children' do
                    let(:start_state) { "Matching 1:\nMatching 2:\nRemoving:\n  Child:\nPreventing:\n  Child:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with a value' do
                    let(:start_state) { "Matching 1:\nMatching 2:\nRemoving:\n  Child:\nPreventing: 5" }
                    it_does_not_apply_the_rule
                  end
                end

                describe 'and a node with a value' do
                  describe 'and a leaf node' do
                    let(:start_state) { "Matching 1:\nMatching 2:\nRemoving: 5\nPreventing:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with children' do
                    let(:start_state) { "Matching 1:\nMatching 2:\nRemoving: 5\nPreventing:\n  Child:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with a value' do
                    let(:start_state) { "Matching 1:\nMatching 2:\nRemoving: 5\nPreventing: 5" }
                    it_does_not_apply_the_rule
                  end
                end
              end

              describe 'and a node with children' do
                describe 'and a leaf node' do
                  describe 'and a leaf node' do
                    let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving:\nPreventing:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with children' do
                    let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving:\nPreventing:\n  Child:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with a value' do
                    let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving:\nPreventing: 5" }
                    it_does_not_apply_the_rule
                  end
                end

                describe 'and a node with children' do
                  describe 'and a leaf node' do
                    let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving:\n  Child:\nPreventing:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with children' do
                    let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving:\n  Child:\nPreventing:\n  Child:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with a value' do
                    let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving:\n  Child:\nPreventing: 5" }
                    it_does_not_apply_the_rule
                  end
                end

                describe 'and a node with a value' do
                  describe 'and a leaf node' do
                    let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving: 5\nPreventing:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with children' do
                    let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving: 5\nPreventing:\n  Child:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with a value' do
                    let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nRemoving: 5\nPreventing: 5" }
                    it_does_not_apply_the_rule
                  end
                end
              end

              describe 'and a node with a value' do
                describe 'and a leaf node' do
                  describe 'and a leaf node' do
                    let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving:\nPreventing:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with children' do
                    let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving:\nPreventing:\n  Child:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with a value' do
                    let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving:\nPreventing: 5" }
                    it_does_not_apply_the_rule
                  end
                end

                describe 'and a node with children' do
                  describe 'and a leaf node' do
                    let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving:\n  Child:\nPreventing:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with children' do
                    let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving:\n  Child:\nPreventing:\n  Child:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with a value' do
                    let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving:\n  Child:\nPreventing: 5" }
                    it_does_not_apply_the_rule
                  end
                end

                describe 'and a node with a value' do
                  describe 'and a leaf node' do
                    let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving: 5\nPreventing:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with children' do
                    let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving: 5\nPreventing:\n  Child:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with a value' do
                    let(:start_state) { "Matching 1:\nMatching 2: 5\nRemoving: 5\nPreventing: 5" }
                    it_does_not_apply_the_rule
                  end
                end
              end
            end

            describe 'matching a node with children' do
              describe 'and a node with children' do
                describe 'and a leaf node' do
                  describe 'and a leaf node' do
                    let(:start_state) { "Matching 1:\n  Child:\nMatching 2:\n  Child:\nRemoving:\nPreventing:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with children' do
                    let(:start_state) { "Matching 1:\n  Child:\nMatching 2:\n  Child:\nRemoving:\nPreventing:\n  Child:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with a value' do
                    let(:start_state) { "Matching 1:\n  Child:\nMatching 2:\n  Child:\nRemoving:\nPreventing: 5" }
                    it_does_not_apply_the_rule
                  end
                end

                describe 'and a node with children' do
                  describe 'and a leaf node' do
                    # TODO
                  end

                  describe 'and a node with children' do
                    # TODO
                  end

                  describe 'and a node with a value' do
                    # TODO
                  end
                end

                describe 'and a node with a value' do
                  describe 'and a leaf node' do
                    let(:start_state) { "Matching 1:\n  Child:\nMatching 2:\n  Child:\nRemoving: 5\nPreventing:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with children' do
                    let(:start_state) { "Matching 1:\n  Child:\nMatching 2:\n  Child:\nRemoving: 5\nPreventing:\n  Child:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with a value' do
                    let(:start_state) { "Matching 1:\n  Child:\nMatching 2:\n  Child:\nRemoving: 5\nPreventing: 5" }
                    it_does_not_apply_the_rule
                  end
                end
              end

              describe 'and a node with a value' do
                describe 'and a leaf node' do
                  describe 'and a leaf node' do
                    let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving:\nPreventing:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with children' do
                    let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving:\nPreventing:\n  Child:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with a value' do
                    let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving:\nPreventing: 5" }
                    it_does_not_apply_the_rule
                  end
                end

                describe 'and a node with children' do
                  describe 'and a leaf node' do
                    let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving:\n  Child:\nPreventing:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with children' do
                    let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving:\n  Child:\nPreventing:\n  Child:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with a value' do
                    let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving:\n  Child:\nPreventing: 5" }
                    it_does_not_apply_the_rule
                  end
                end

                describe 'and a node with a value' do
                  describe 'and a leaf node' do
                    let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving: 5\nPreventing:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with children' do
                    let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving: 5\nPreventing:\n  Child:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with a value' do
                    let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nRemoving: 5\nPreventing: 5" }
                    it_does_not_apply_the_rule
                  end
                end
              end
            end

            describe 'matching a node with a value' do
              describe 'and a node with a value' do
                describe 'and a leaf node' do
                  describe 'and a leaf node' do
                    let(:start_state) { "Matching 1: 5\nMatching 2: 5\nRemoving:\nPreventing:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with children' do
                    let(:start_state) { "Matching 1: 5\nMatching 2: 5\nRemoving:\nPreventing:\n  Child:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with a value' do
                    let(:start_state) { "Matching 1: 5\nMatching 2: 5\nRemoving:\nPreventing: 5" }
                    it_does_not_apply_the_rule
                  end
                end

                describe 'and a node with children' do
                  describe 'and a leaf node' do
                    let(:start_state) { "Matching 1: 5\nMatching 2: 5\nRemoving:\n  Child:\nPreventing:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with children' do
                    let(:start_state) { "Matching 1: 5\nMatching 2: 5\nRemoving:\n  Child:\nPreventing:\n  Child:" }
                    it_does_not_apply_the_rule
                  end

                  describe 'and a node with a value' do
                    let(:start_state) { "Matching 1: 5\nMatching 2: 5\nRemoving:\n  Child:\nPreventing: 5" }
                    it_does_not_apply_the_rule
                  end
                end

                describe 'and a node with a value' do
                  describe 'and a leaf node' do
                    # TODO
                  end

                  describe 'and a node with children' do
                    # TODO
                  end

                  describe 'and a node with a value' do
                    # TODO
                  end
                end
              end
            end
          end
        end

        describe 'and a creating condition' do
          let(:rules) { <<-EOS }
            Matching 1: X
            Matching 2: X
            +Creating: X
            !Matched:
            +Matched:
          EOS

          it_does_not_allow_the_variable_to_be_used_in_a_code_segment "X"

          describe 'matching a leaf node' do
            describe 'and a leaf node' do
              let(:start_state) { "Matching 1:\nMatching 2:" }
              it_applies_the_rule "Matching 1:\nMatching 2:\nCreating:\nMatched:"
            end

            describe 'and a node with children' do
              let(:start_state) { "Matching 1:\nMatching 2:\n  Child:" }
              it_does_not_apply_the_rule
            end

            describe 'and a node with a value' do
              let(:start_state) { "Matching 1:\nMatching 2: 5" }
              it_does_not_apply_the_rule
            end
          end

          describe 'matching a node with children' do
            describe 'and a node with children' do
              # TODO
            end

            describe 'and a node with a value' do
              let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5" }
              it_does_not_apply_the_rule
            end
          end

          describe 'matching a node with a value' do
            describe 'and a node with a value' do
              describe 'that are equal integers' do
                let(:start_state) { "Matching 1: 5\nMatching 2: 5" }
                it_applies_the_rule "Matching 1: 5\nMatching 2: 5\nCreating: 5\nMatched:"
              end

              describe 'that are unequal integers' do
                let(:start_state) { "Matching 1: 5\nMatching 2: 4" }
                it_does_not_apply_the_rule
              end

              describe 'that are equal decimals' do
                let(:start_state) { "Matching 1: 5.3\nMatching 2: 5.3" }
                it_applies_the_rule "Matching 1: 5.3\nMatching 2: 5.3\nCreating: 5.3\nMatched:"
              end

              describe 'that are unequal decimals' do
                let(:start_state) { "Matching 1: 5.3\nMatching 2: 4.3" }
                it_does_not_apply_the_rule
              end

              describe 'that are an integer and a decimal' do
                let(:start_state) { "Matching 1: 5\nMatching 2: 5.0" }
                it_does_not_apply_the_rule
              end
            end
          end

          describe 'and a preventing condition' do
            let(:rules) { <<-EOS }
              Matching 1: X
              Matching 2: X
              +Creating: X
              !Preventing: X
              !Matched:
              +Matched:
            EOS

            it_does_not_allow_the_variable_to_be_used_in_a_code_segment "X"

            describe 'matching a leaf node' do
              describe 'and a leaf node' do
                describe 'and a leaf node' do
                  let(:start_state) { "Matching 1:\nMatching 2:\nPreventing:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with children' do
                  let(:start_state) { "Matching 1:\nMatching 2:\nPreventing:\n  Child:" }
                  it_applies_the_rule "Matching 1:\nMatching 2:\nPreventing:\n  Child:\nCreating:\nMatched:"
                end

                describe 'and a node with a value' do
                  let(:start_state) { "Matching 1:\nMatching 2:\nPreventing: 5" }
                  it_applies_the_rule "Matching 1:\nMatching 2:\nPreventing: 5\nCreating:\nMatched:"
                end
              end

              describe 'and a node with children' do
                describe 'and a leaf node' do
                  let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nPreventing:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with children' do
                  let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nPreventing:\n  Child:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with a value' do
                  let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nPreventing: 5" }
                  it_does_not_apply_the_rule
                end
              end

              describe 'and a node with a value' do
                describe 'and a leaf node' do
                  let(:start_state) { "Matching 1:\nMatching 2: 5\nPreventing:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with children' do
                  let(:start_state) { "Matching 1:\nMatching 2: 5\nPreventing:\n  Child:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with a value' do
                  let(:start_state) { "Matching 1:\nMatching 2: 5\nPreventing: 5" }
                  it_does_not_apply_the_rule
                end
              end
            end

            describe 'matching a node with children' do
              describe 'and a node with children' do
                describe 'and a leaf node' do
                  # TODO
                end

                describe 'and a node with children' do
                  # TODO
                end

                describe 'and a node with a value' do
                  # TODO
                end
              end

              describe 'and a node with a value' do
                describe 'and a leaf node' do
                  let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nPreventing:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with children' do
                  let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nPreventing:\n  Child:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with a value' do
                  let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nPreventing: 5" }
                  it_does_not_apply_the_rule
                end
              end
            end

            describe 'matching a node with a value' do
              describe 'and a node with a value' do
                describe 'and a leaf node' do
                  # TODO
                end

                describe 'and a node with children' do
                  # TODO
                end

                describe 'and a node with a value' do
                  # TODO
                end
              end
            end
          end
        end

        describe 'and a preventing condition' do
          let(:rules) { <<-EOS }
            Matching 1: X
            Matching 2: X
            !Preventing: X
            !Matched:
            +Matched:
          EOS

          it_does_not_allow_the_variable_to_be_used_in_a_code_segment "X"

          describe 'matching a leaf node' do
            describe 'and a leaf node' do
              describe 'and a leaf node' do
                let(:start_state) { "Matching 1:\nMatching 2:\nPreventing:" }
                it_does_not_apply_the_rule
              end

              describe 'and a node with children' do
                let(:start_state) { "Matching 1:\nMatching 2:\nPreventing:\n  Child:" }
                it_applies_the_rule "Matching 1:\nMatching 2:\nPreventing:\n  Child:\nMatched:"
              end

              describe 'and a node with a value' do
                let(:start_state) { "Matching 1:\nMatching 2:\nPreventing: 5" }
                it_applies_the_rule "Matching 1:\nMatching 2:\nPreventing: 5\nMatched:"
              end
            end

            describe 'and a node with children' do
              describe 'and a leaf node' do
                let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nPreventing:" }
                it_does_not_apply_the_rule
              end

              describe 'and a node with children' do
                let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nPreventing:\n  Child:" }
                it_does_not_apply_the_rule
              end

              describe 'and a node with a value' do
                let(:start_state) { "Matching 1:\nMatching 2:\n  Child:\nPreventing: 5" }
                it_does_not_apply_the_rule
              end
            end

            describe 'and a node with a value' do
              describe 'and a leaf node' do
                let(:start_state) { "Matching 1:\nMatching 2: 5\nPreventing:" }
                it_does_not_apply_the_rule
              end

              describe 'and a node with children' do
                let(:start_state) { "Matching 1:\nMatching 2: 5\nPreventing:\n  Child:" }
                it_does_not_apply_the_rule
              end

              describe 'and a node with a value' do
                let(:start_state) { "Matching 1:\nMatching 2: 5\nPreventing: 5" }
                it_does_not_apply_the_rule
              end
            end
          end

          describe 'matching a node with children' do
            describe 'and a node with children' do
              describe 'and a leaf node' do
                # TODO
              end

              describe 'and a node with children' do
                # TODO
              end

              describe 'and a node with a value' do
                # TODO
              end
            end

            describe 'and a node with a value' do
              describe 'and a leaf node' do
                let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nPreventing:" }
                it_does_not_apply_the_rule
              end

              describe 'and a node with children' do
                let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nPreventing:\n  Child:" }
                it_does_not_apply_the_rule
              end

              describe 'and a node with a value' do
                let(:start_state) { "Matching 1:\n  Child:\nMatching 2: 5\nPreventing: 5" }
                it_does_not_apply_the_rule
              end
            end
          end

          describe 'matching a node with a value' do
            describe 'and a node with a value' do
              describe 'and a leaf node' do
                # TODO
              end

              describe 'and a node with children' do
                # TODO
              end

              describe 'and a node with a value' do
                # TODO
              end
            end
          end
        end
      end

      describe 'and a removing condition' do
        let(:rules) { <<-EOS }
          Matching: X
          -Removing: X
        EOS

        it_does_not_allow_the_variable_to_be_used_in_a_code_segment "X"

        describe 'matching a leaf node' do
          describe 'and a leaf node' do
            let(:start_state) { "Matching:\nRemoving:" }
            it_applies_the_rule "Matching:"
          end

          describe 'and a node with children' do
            let(:start_state) { "Matching:\nRemoving:\n  Child:" }
            it_does_not_apply_the_rule
          end

          describe 'and a node with a value' do
            let(:start_state) { "Matching:\nRemoving: 5" }
            it_does_not_apply_the_rule
          end
        end

        describe 'matching a node with children' do
          describe 'and a node with children' do
            # TODO
          end

          describe 'and a node with a value' do
            let(:start_state) { "Matching:\n  Child:\nRemoving: 5" }
            it_does_not_apply_the_rule
          end
        end

        describe 'matching a node with a value' do
          describe 'and a node with a value' do
            describe 'that are equal integers' do
              let(:start_state) { "Matching: 5\nRemoving: 5" }
              it_applies_the_rule "Matching: 5"
            end

            describe 'that are unequal integers' do
              let(:start_state) { "Matching: 5\nRemoving: 4" }
              it_does_not_apply_the_rule
            end

            describe 'that are equal decimals' do
              let(:start_state) { "Matching: 5.3\nRemoving: 5.3" }
              it_applies_the_rule "Matching: 5.3"
            end

            describe 'that are unequal decimals' do
              let(:start_state) { "Matching: 5.3\nRemoving: 4.3" }
              it_does_not_apply_the_rule
            end

            describe 'that are an integer and a decimal' do
              let(:start_state) { "Matching: 5\nRemoving: 5.0" }
              it_does_not_apply_the_rule
            end
          end
        end

        describe 'and a creating condition' do
          let(:rules) { <<-EOS }
            Matching: X
            -Removing: X
            +Creating: X
          EOS

          it_does_not_allow_the_variable_to_be_used_in_a_code_segment "X"

          describe 'matching a leaf node' do
            describe 'and a leaf node' do
              let(:start_state) { "Matching:\nRemoving:" }
              it_applies_the_rule "Matching:\nCreating:"
            end

            describe 'and a node with children' do
              let(:start_state) { "Matching:\nRemoving:\n  Child:" }
              it_does_not_apply_the_rule
            end

            describe 'and a node with a value' do
              let(:start_state) { "Matching:\nRemoving: 5" }
              it_does_not_apply_the_rule
            end
          end

          describe 'matching a node with children' do
            describe 'and a node with children' do
              # TODO
            end

            describe 'and a node with a value' do
              let(:start_state) { "Matching:\n  Child:\nRemoving: 5" }
              it_does_not_apply_the_rule
            end
          end

          describe 'matching a node with a value' do
            describe 'and a node with a value' do
              describe 'that are equal integers' do
                let(:start_state) { "Matching: 5\nRemoving: 5" }
                it_applies_the_rule "Matching: 5\nCreating: 5"
              end

              describe 'that are unequal integers' do
                let(:start_state) { "Matching: 5\nRemoving: 4" }
                it_does_not_apply_the_rule
              end

              describe 'that are equal decimals' do
                let(:start_state) { "Matching: 5.3\nRemoving: 5.3" }
                it_applies_the_rule "Matching: 5.3\nCreating: 5.3"
              end

              describe 'that are unequal decimals' do
                let(:start_state) { "Matching: 5.3\nRemoving: 4.3" }
                it_does_not_apply_the_rule
              end

              describe 'that are an integer and a decimal' do
                let(:start_state) { "Matching: 5\nRemoving: 5.0" }
                it_does_not_apply_the_rule
              end
            end
          end

          describe 'and a preventing condition' do
            let(:rules) { <<-EOS }
              Matching: X
              -Removing: X
              +Creating: X
              !Preventing: X
            EOS

            it_does_not_allow_the_variable_to_be_used_in_a_code_segment "X"

            describe 'matching a leaf node' do
              describe 'and a leaf node' do
                describe 'and a leaf node' do
                  let(:start_state) { "Matching:\nRemoving:\nPreventing:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with children' do
                  let(:start_state) { "Matching:\nRemoving:\nPreventing:\n  Child:" }
                  it_applies_the_rule "Matching:\nCreating:\nPreventing:\n  Child:"
                end

                describe 'and a node with a value' do
                  let(:start_state) { "Matching:\nRemoving:\nPreventing: 5" }
                  it_applies_the_rule "Matching:\nCreating:\nPreventing: 5"
                end
              end

              describe 'and a node with children' do
                describe 'and a leaf node' do
                  let(:start_state) { "Matching:\nRemoving:\n  Child:\nPreventing:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with children' do
                  let(:start_state) { "Matching:\nRemoving:\n  Child:\nPreventing:\n  Child:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with a value' do
                  let(:start_state) { "Matching:\nRemoving:\n  Child:\nPreventing: 5" }
                  it_does_not_apply_the_rule
                end
              end

              describe 'and a node with a value' do
                describe 'and a leaf node' do
                  let(:start_state) { "Matching:\nRemoving: 5\nPreventing:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with children' do
                  let(:start_state) { "Matching:\nRemoving: 5\nPreventing:\n  Child:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with a value' do
                  let(:start_state) { "Matching:\nRemoving: 5\nPreventing: 5" }
                  it_does_not_apply_the_rule
                end
              end
            end

            describe 'matching a node with children' do
              describe 'and a node with children' do
                describe 'and a leaf node' do
                  # TODO
                end

                describe 'and a node with children' do
                  # TODO
                end

                describe 'and a node with a value' do
                  # TODO
                end
              end

              describe 'and a node with a value' do
                describe 'and a leaf node' do
                  let(:start_state) { "Matching:\n  Child:\nRemoving: 5\nPreventing:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with children' do
                  let(:start_state) { "Matching:\n  Child:\nRemoving: 5\nPreventing:\n  Child:" }
                  it_does_not_apply_the_rule
                end

                describe 'and a node with a value' do
                  let(:start_state) { "Matching:\n  Child:\nRemoving: 5\nPreventing: 5" }
                  it_does_not_apply_the_rule
                end
              end
            end

            describe 'matching a node with a value' do
              describe 'and a node with a value' do
                describe 'and a leaf node' do
                  # TODO
                end

                describe 'and a node with children' do
                  # TODO
                end

                describe 'and a node with a value' do
                  # TODO
                end
              end
            end
          end
        end
      end

      describe 'and a creating condition' do
        let(:rules) { <<-EOS }
          Matching: X
          +Creating: X
          !Matched:
          +Matched:
        EOS

        describe 'used independently later' do
          let(:rules) { <<-EOS }
            Matching: X
            +Creating: X
            !Matched:
            +Matched:

            Creating: X
            !Modified:
            +Modified:
            < #{target}->value_type = integer;
            < #{target}->integer_value = 5;
          EOS
          let(:target) { '$X' }

          describe 'matching a leaf node' do
            let(:start_state) { "Matching:" }
            it_applies_the_rule "Matching:\nCreating: 5\nMatched:\nModified:"
          end

          describe 'matching a node with children' do
            let(:start_state) { "Matching:\n  Child:" }
            let(:target) { '$X->children' }
            it_applies_the_rule "Matching:\n  Child:\nCreating:\n  Child: 5\nMatched:\nModified:"
          end

          describe 'matching a node with a value' do
            let(:start_state) { "Matching: 4" }
            it_applies_the_rule "Matching: 4\nCreating: 5\nMatched:\nModified:"
          end
        end

        describe 'matching a leaf node' do
          let(:start_state) { "Matching:" }
          it_applies_the_rule "Matching:\nCreating:\nMatched:"
          it_allows_the_variable_to_be_used_in_a_code_segment "X", "Matching"
        end

        describe 'matching a node with children' do
          let(:start_state) { "Matching:" }
          it_applies_the_rule "Matching:\n  Child:\nCreating:\n  Child:\nMatched:"
          it_allows_the_variable_to_be_used_in_a_code_segment "X", "Matching"
        end

        describe 'matching a node with a value' do
          let(:start_state) { "Matching:" }
          it_applies_the_rule "Matching: 5\nCreating: 5\nMatched:"
          it_allows_the_variable_to_be_used_in_a_code_segment "X", "Matching"
        end

        describe 'and a preventing condition' do
          let(:rules) { <<-EOS }
            Matching: X
            +Creating: X
            !Preventing: X
            !Matched:
            +Matched:
          EOS

          describe 'matching a leaf node' do
            describe 'and a leaf node' do
              let(:start_state) { "Matching:\nPreventing:" }
              it_does_not_apply_the_rule
            end

            describe 'and a node with children' do
              let(:start_state) { "Matching:\nPreventing:\n  Child:" }
              it_applies_the_rule "Matching:\nCreating:\nPreventing:\n  Child:\nMatched:"
              it_allows_the_variable_to_be_used_in_a_code_segment "X", "Matching"
            end

            describe 'and a node with a value' do
              let(:start_state) { "Matching:\nPreventing: 5" }
              it_applies_the_rule "Matching:\nCreating:\nPreventing: 5\nMatched:"
              it_allows_the_variable_to_be_used_in_a_code_segment "X", "Matching"
            end
          end

          describe 'matching a node with children' do
            describe 'and a leaf node' do
              let(:start_state) { "Matching:\n  Child:\nPreventing:" }
              it_applies_the_rule "Matching:\n  Child:\nCreating:\n  Child:\nPreventing:\nMatched:"
              it_allows_the_variable_to_be_used_in_a_code_segment "X", "Matching"
            end

            describe 'and a node with children' do
              # TODO
            end

            describe 'and a node with a value' do
              let(:start_state) { "Matching:\n  Child:\nPreventing: 5" }
              it_applies_the_rule "Matching:\n  Child:\nCreating:\n  Child:\nPreventing: 5\nMatched:"
              it_allows_the_variable_to_be_used_in_a_code_segment "X", "Matching"
            end
          end

          describe 'matching a node with a value' do
            describe 'and a leaf node' do
              let(:start_state) { "Matching: 5\nPreventing:" }
              it_applies_the_rule "Matching: 5\nCreating: 5\nPreventing:\nMatched:"
              it_allows_the_variable_to_be_used_in_a_code_segment "X", "Matching"
            end

            describe 'and a node with children' do
              let(:start_state) { "Matching: 5\nPreventing:\n  Child:" }
              it_applies_the_rule "Matching: 5\nCreating: 5\nPreventing:\n  Child:\nMatched:"
              it_allows_the_variable_to_be_used_in_a_code_segment "X", "Matching"
            end

            describe 'and a node with a value' do
              # TODO
            end
          end
        end
      end

      describe 'and a preventing condition' do
        let(:rules) { <<-EOS }
          Matching: X
          !Preventing: X
          !Matched:
          +Matched:
        EOS

        describe 'matching a leaf node' do
          describe 'and a leaf node' do
            let(:start_state) { "Matching:\nPreventing:" }
            it_does_not_apply_the_rule
          end

          describe 'and a node with children' do
            let(:start_state) { "Matching:\nPreventing:\n  Child:" }
            it_applies_the_rule "Matching:\nPreventing:\n  Child:\nMatched:"
            it_allows_the_variable_to_be_used_in_a_code_segment "X", "Matching"
          end

          describe 'and a node with a value' do
            let(:start_state) { "Matching:\nPreventing: 5" }
            it_applies_the_rule "Matching:\nPreventing: 5\nMatched:"
            it_allows_the_variable_to_be_used_in_a_code_segment "X", "Matching"
          end
        end

        describe 'matching a node with children' do
          describe 'and a leaf node' do
            let(:start_state) { "Matching:\n  Child:\nPreventing:" }
            it_applies_the_rule "Matching:\n  Child:\nPreventing:\nMatched:"
            it_allows_the_variable_to_be_used_in_a_code_segment "X", "Matching"
          end

          describe 'and a node with children' do
            # TODO
          end

          describe 'and a node with a value' do
            let(:start_state) { "Matching:\n  Child:\nPreventing: 5" }
            it_applies_the_rule "Matching:\n  Child:\nPreventing: 5\nMatched:"
            it_allows_the_variable_to_be_used_in_a_code_segment "X", "Matching"
          end
        end

        describe 'matching a node with a value' do
          describe 'and a leaf node' do
            let(:start_state) { "Matching: 5\nPreventing:" }
            it_applies_the_rule "Matching: 5\nPreventing:\nMatched:"
            it_allows_the_variable_to_be_used_in_a_code_segment "X", "Matching"
          end

          describe 'and a node with children' do
            let(:start_state) { "Matching: 5\nPreventing:\n  Child:" }
            it_applies_the_rule "Matching: 5\nPreventing:\n  Child:\nMatched:"
            it_allows_the_variable_to_be_used_in_a_code_segment "X", "Matching"
          end

          describe 'and a node with a value' do
            # TODO
          end
        end
      end
    end

    describe 'referenced in a removing condition' do
      let(:rules) { "-Removing: X" }

      describe 'matching a leaf node' do
        let(:start_state) { "Removing:" }
        it_applies_the_rule ""
        it_allows_the_variable_to_be_used_in_a_code_segment "X", "Removing"
      end

      describe 'matching a node with children' do
        let(:start_state) { "Removing:\n  Child:" }
        it_applies_the_rule ""
        it_allows_the_variable_to_be_used_in_a_code_segment "X", "Removing"
      end

      describe 'matching a node with a value' do
        let(:start_state) { "Removing: 5" }
        it_applies_the_rule ""
        it_allows_the_variable_to_be_used_in_a_code_segment "X", "Removing"
      end

      describe 'and another removing condition' do
        let(:rules) { <<-EOS }
          -Removing 1: X
          -Removing 2: X
        EOS

        it_does_not_allow_the_variable_to_be_used_in_a_code_segment "X"

        describe 'matching a leaf node' do
          describe 'and a leaf node' do
            let(:start_state) { "Removing 1:\nRemoving 2:" }
            it_applies_the_rule ""
          end

          describe 'and a node with children' do
            let(:start_state) { "Removing 1:\nRemoving 2:\n  Child:" }
            it_does_not_apply_the_rule
          end

          describe 'and a node with a value' do
            let(:start_state) { "Removing 1:\nRemoving 2: 5" }
            it_does_not_apply_the_rule
          end
        end

        describe 'matching a node with children' do
          describe 'and a node with children' do
            # TODO
          end

          describe 'and a node with a value' do
            let(:start_state) { "Removing 1:\n  Child:\nRemoving 2: 5" }
            it_does_not_apply_the_rule
          end
        end

        describe 'matching a node with a value' do
          describe 'and a node with a value' do
            describe 'that are equal integers' do
              let(:start_state) { "Removing 1: 5\nRemoving 2: 5" }
              it_applies_the_rule ""
            end

            describe 'that are unequal integers' do
              let(:start_state) { "Removing 1: 5\nRemoving 2: 4" }
              it_does_not_apply_the_rule
            end

            describe 'that are equal decimals' do
              let(:start_state) { "Removing 1: 5.3\nRemoving 2: 5.3" }
              it_applies_the_rule ""
            end

            describe 'that are unequal decimals' do
              let(:start_state) { "Removing 1: 5.3\nRemoving 2: 4.3" }
              it_does_not_apply_the_rule
            end

            describe 'that are an integer and a decimal' do
              let(:start_state) { "Removing 1: 5\nRemoving 2: 5.3" }
              it_does_not_apply_the_rule
            end
          end
        end
      end

      describe 'and a creating condition' do
        let(:rules) { <<-EOS }
          -Removing: X
          +Creating: X
        EOS

        describe 'matching a leaf node' do
          let(:start_state) { "Removing:" }
          it_applies_the_rule "Creating:"
          it_allows_the_variable_to_be_used_in_a_code_segment "X", "Removing"
        end

        describe 'matching a node with children' do
          let(:start_state) { "Removing:\n  Child:" }
          it_applies_the_rule "Creating:\n  Child:"
          it_allows_the_variable_to_be_used_in_a_code_segment "X", "Removing"
        end

        describe 'matching a node with a value' do
          let(:start_state) { "Removing: 5" }
          it_applies_the_rule "Creating: 5"
          it_allows_the_variable_to_be_used_in_a_code_segment "X", "Removing"
        end

        describe 'and a preventing condition' do
          let(:rules) { <<-EOS }
            -Removing: X
            +Creating: X
            !Preventing: X
          EOS

          describe 'matching a leaf node' do
            describe 'and a leaf node' do
              let(:start_state) { "Removing:\nPreventing:" }
              it_does_not_apply_the_rule
            end

            describe 'and a node with children' do
              let(:start_state) { "Removing:\nPreventing:\n  Child:" }
              it_applies_the_rule "Creating:\nPreventing:\n  Child:"
              it_allows_the_variable_to_be_used_in_a_code_segment "X", "Removing"
            end

            describe 'and a node with a value' do
              let(:start_state) { "Removing:\nPreventing: 5" }
              it_applies_the_rule "Creating:\nPreventing: 5"
              it_allows_the_variable_to_be_used_in_a_code_segment "X", "Removing"
            end
          end

          describe 'matching a node with children' do
            describe 'and a leaf node' do
              let(:start_state) { "Removing:\n  Child:\nPreventing:" }
              it_applies_the_rule "Creating:\n  Child:\nPreventing:"
              it_allows_the_variable_to_be_used_in_a_code_segment "X", "Removing"
            end

            describe 'and a node with children' do
              # TODO
            end

            describe 'and a node with a value' do
              let(:start_state) { "Removing:\n  Child:\nPreventing: 5" }
              it_applies_the_rule "Creating:\n  Child:\nPreventing: 5"
              it_allows_the_variable_to_be_used_in_a_code_segment "X", "Removing"
            end
          end

          describe 'matching a node with a value' do
            describe 'and a leaf node' do
              let(:start_state) { "Removing: 5\nPreventing:" }
              it_applies_the_rule "Creating: 5\nPreventing:"
              it_allows_the_variable_to_be_used_in_a_code_segment "X", "Removing"
            end

            describe 'and a node with children' do
              let(:start_state) { "Removing: 5\nPreventing:\n  Child:" }
              it_applies_the_rule "Creating: 5\nPreventing:\n  Child:"
              it_allows_the_variable_to_be_used_in_a_code_segment "X", "Removing"
            end

            describe 'and a node with a value' do
              # TODO
            end
          end
        end
      end

      describe 'and a preventing condition' do
        let(:rules) { <<-EOS }
          -Removing: X
          !Preventing: X
        EOS

        describe 'matching a leaf node' do
          describe 'and a leaf node' do
            let(:start_state) { "Removing:\nPreventing:" }
            it_does_not_apply_the_rule
          end

          describe 'and a node with children' do
            let(:start_state) { "Removing:\nPreventing:\n  Child:" }
            it_applies_the_rule "Preventing:\n  Child:"
            it_allows_the_variable_to_be_used_in_a_code_segment "X", "Removing"
          end

          describe 'and a node with a value' do
            let(:start_state) { "Removing:\nPreventing: 5" }
            it_applies_the_rule "Preventing: 5"
            it_allows_the_variable_to_be_used_in_a_code_segment "X", "Removing"
          end
        end

        describe 'matching a node with children' do
          describe 'and a leaf node' do
            let(:start_state) { "Removing:\n  Child:\nPreventing:" }
            it_applies_the_rule "Preventing:"
            it_allows_the_variable_to_be_used_in_a_code_segment "X", "Removing"
          end

          describe 'and a node with children' do
            # TODO
          end

          describe 'and a node with a value' do
            let(:start_state) { "Removing:\n  Child:\nPreventing: 5" }
            it_applies_the_rule "Preventing: 5"
            it_allows_the_variable_to_be_used_in_a_code_segment "X", "Removing"
          end
        end

        describe 'matching a node with a value' do
          describe 'and a leaf node' do
            let(:start_state) { "Removing: 5\nPreventing:" }
            it_applies_the_rule "Preventing:"
            it_allows_the_variable_to_be_used_in_a_code_segment "X", "Removing"
          end

          describe 'and a node with children' do
            let(:start_state) { "Removing: 5\nPreventing:\n  Child:" }
            it_applies_the_rule "Preventing:\n  Child:"
            it_allows_the_variable_to_be_used_in_a_code_segment "X", "Removing"
          end

          describe 'and a node with a value' do
            # TODO
          end
        end
      end
    end

    describe 'referenced in a creating condition' do
      let(:rules) { <<-EOS }
        +Creating: X
        !Matched:
        +Matched:
      EOS

      let(:start_state) { "" }
      it_applies_the_rule "Creating:\nMatched:"
      it_allows_the_variable_to_be_used_in_a_code_segment "X", "(null)"

      describe 'and another creating condition' do
        let(:rules) { <<-EOS }
          +Creating 1: X
          +Creating 2: X
          !Matched:
          +Matched:
        EOS

        let(:start_state) { "" }
        it_applies_the_rule "Creating 1:\nCreating 2:\nMatched:"
        it_allows_the_variable_to_be_used_in_a_code_segment "X", "(null)"

        it 'does not link the nodes'
      end

      describe 'and a preventing condition' do
        let(:rules) { <<-EOS }
          +Creating: X
          !Preventing: X
          !Matched:
          +Matched:
        EOS

        let(:start_state) { "" }
        it_causes_a_compile_error
      end
    end

    describe 'referenced in a preventing condition' do
      let(:rules) { <<-EOS }
        !Preventing: X
        !Matched:
        +Matched:
      EOS

      let(:start_state) { "" }
      it_causes_a_compile_error

      describe 'and another preventing condition' do
        let(:rules) { <<-EOS }
          !Preventing 1: X
          !Preventing 2: X
          !Matched:
          +Matched:
        EOS

        let(:start_state) { "" }
        it_causes_a_compile_error
      end
    end
  end

  describe 'conditions at the top level of a rule' do
    let(:rules) { <<-EOS }
      -Foo:
      -Bar:
    EOS

    describe 'in unordered contexts' do
      let(:start_state) { <<-EOS }
        Baz:
          Bar:
          Foo:
      EOS
      it_applies_the_rule "Baz:"
    end

    describe 'in ordered contexts' do
      describe 'matching from the beginning' do
        let(:start_state) { <<-EOS }
          Baz::
            Foo:
            Bar:
        EOS
        it_applies_the_rule "Baz::"
      end

      describe 'matching from the middle' do
        let(:start_state) { <<-EOS }
          Baz::
            Qux:
            Foo:
            Bar:
        EOS
        it_applies_the_rule "Baz::"
      end

      describe 'matching out of order' do
        let(:start_state) { <<-EOS }
          Baz::
            Bar:
            Foo:
        EOS
        it_does_not_apply_the_rule
      end
    end
  end
end
