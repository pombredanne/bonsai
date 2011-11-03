require File.dirname(__FILE__) + '/parser'

class Compiler
  def compile program
    rules = Parser.new.parse_rules program

    <<-EOS
      #include <stdlib.h>
      #include <stdio.h>
      #include <string.h>

      #{File.read File.dirname(__FILE__) + '/../types.h'}

      #{File.read File.dirname(__FILE__) + '/runtime.c'}

      #{apply_rules rules}
    EOS
  end

  private
    def apply_rules rules
      apply_rules = <<-EOS
        typedef struct Match {
        } Match;
      EOS

      apply_rules += rules.map {|rule| "#{rule_matches rule}\n#{transform_rule rule}"}.join "\n"

      apply_rules += <<-EOS
        bool apply_rules(Node* node) {
          Match* match;
      EOS

      apply_rules += rules.map do |rule|
        <<-EOS
          if ((match = rule_#{rule.object_id}_matches(node)) && transform_rule_#{rule.object_id}(match))
            return true;
        EOS
      end.join ' else '

      apply_rules + <<-EOS
          return false;
        }
      EOS
    end

    def rule_matches rule
      rule_matches = <<-EOS
        Match* rule_#{rule.object_id}_matches(Node* node) {
      EOS

      if rule.conditions_can_match_in_order?
        rule_matches += <<-EOS
          if (node->children_are_ordered) {
        EOS

        rule_matches += <<-EOS
            if (false) { // TODO: if the conditions match the nodes in order
        EOS

        if rule.must_match_all_nodes?
          rule_matches += <<-EOS
              if (false) // TODO: if there are no unmatched nodes
          EOS
        end

        rule_matches += <<-EOS
              return NULL; // TODO: return the matched nodes
            }
        EOS

        unless rule.conditions_can_match_ordered_nodes_out_of_order?
          rule_matches += <<-EOS
            return NULL;
          EOS
        end

        rule_matches += <<-EOS
          }
        EOS
      end

      if rule.conditions_can_match_out_of_order?
        rule_matches += <<-EOS
          if (false) // TODO: if any preventing rule matches one of the node's children
            return NULL;

          if (false) { // TODO: if there is a one-to-one mapping of singly-matched conditions to node's children
            // TODO: greedily map multiply-matched conditions to node's unmatched children
        EOS

        if rule.must_match_all_nodes?
          rule_matches += <<-EOS
            if (false) // TODO: if there are any unmatched nodes
              return NULL;
          EOS
        end

        rule_matches += <<-EOS
            // TODO: add creating conditions to the match
            return NULL; // TODO: return the match
          }
        EOS
      end

      rule_matches + <<-EOS
          return NULL;
        }
      EOS
    end

    def transform_rule rule
      <<-EOS
        bool transform_rule_#{rule.object_id}(Match* match) {
          return false;
        }
      EOS
    end
end
