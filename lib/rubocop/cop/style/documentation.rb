# frozen_string_literal: true

module RuboCop
  module Cop
    module Style
      # This cop checks for missing top-level documentation of classes and
      # modules. Classes with no body are exempt from the check and so are
      # namespace modules - modules that have nothing in their bodies except
      # classes, other modules, constant definitions or constant visibility
      # declarations.
      #
      # The documentation requirement is annulled if the class or module has
      # a "#:nodoc:" comment next to it. Likewise, "#:nodoc: all" does the
      # same for all its children.
      #
      # @example
      #   # bad
      #   class Person
      #     # ...
      #   end
      #
      #   # good
      #   # Description/Explanation of Person class
      #   class Person
      #     # ...
      #   end
      #
      class Documentation < Cop
        include DocumentationComment

        MSG = 'Missing top-level %<type>s documentation comment.'

        def_node_matcher :constant_definition?, '{class module casgn}'
        def_node_search :outer_module, '(const (const nil? _) _)'
        def_node_matcher :constant_visibility_declaration?, <<-PATTERN
          (send nil? {:public_constant :private_constant} ({sym str} _))
        PATTERN

        def_node_search :private_constants, <<~PATTERN
          (send nil? :private_constant ({sym str} $_)+)
        PATTERN

        def_node_matcher :private_constant_declaration?, <<~PATTERN
          (send nil? :private_constant ({sym str} %1)+)
        PATTERN

        def_node_matcher :constant_definitions, <<~PATTERN
          ({class module casgn} (const nil? $_))
        PATTERN

        def on_class(node)
          return unless node.body

          check(node, node.body, :class)
        end

        def on_module(node)
          check(node, node.body, :module)
        end

        private

        def check(node, body, type)
          return if namespace?(body)
          return if private_constant?(node) && !require_for_private_objects?
          return if documentation_comment?(node) || nodoc_comment?(node)
          return if compact_namespace?(node) &&
            nodoc_comment?(outer_module(node).first)

          add_offense(node,
                      location: :keyword,
                      message: format(MSG, type: type))
        end

        def namespace?(node)
          return false unless node

          if node.begin_type?
            node.children.all?(&method(:constant_declaration?))
          else
            constant_definition?(node)
          end
        end

        def constant_declaration?(node)
          constant_definition?(node) || constant_visibility_declaration?(node)
        end

        def private_constant?(node)
          # return unless node.parent

          # binding.irb

          # types = %i[begin class module casgn]

          compute_name = node.defined_module_name

          node.each_ancestor.any? do |ancestor|
            unless ancestor.begin_type?
              compute_name = "#{ancestor.defined_module_name}::#{compute_name}"
            end

            # child_name = nil
            #
            # ancestor.each_node(:send, :class, :module, :casgn) do |child|
            #   if child.begin_type?
            #
            #   else
            #     child_name = if child_name
            #                    "#{child_name}::#{constant_definitions(child)}"
            #                  else
            #                    constant_definitions(child)
            #                  end
            #   end
            #   unless child.begin_type?
            #     child_name = "#{child_name}::#{child.defined_module_name}"
            #   end
            # end
            private_constants(ancestor).to_a.flatten.map(&:to_s) \
                                       .include? compute_name
          end

          # private_constants(node.parent).to_a.flatten.map(&:to_s) \
          #   .include? node.defined_module_name
        end

        def require_for_private_objects?
          cop_config.fetch('RequireForPrivateObjects', false)
        end

        def compact_namespace?(node)
          node.loc.name.source =~ /::/
        end

        # First checks if the :nodoc: comment is associated with the
        # class/module. Unless the element is tagged with :nodoc:, the search
        # proceeds to check its ancestors for :nodoc: all.
        # Note: How end-of-line comments are associated with code changed in
        # parser-2.2.0.4.
        def nodoc_comment?(node, require_all = false)
          return false unless node&.children&.first

          nodoc = nodoc(node)

          return true if same_line?(nodoc, node) && nodoc?(nodoc, require_all)

          nodoc_comment?(node.parent, true)
        end

        def nodoc?(comment, require_all = false)
          comment.text =~ /^#\s*:nodoc:#{"\s+all\s*$" if require_all}/
        end

        def nodoc(node)
          processed_source.ast_with_comments[node.children.first].first
        end
      end
    end
  end
end
