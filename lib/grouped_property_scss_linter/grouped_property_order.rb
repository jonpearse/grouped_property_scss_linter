module SCSSLint
  class Linter::GroupedPropertyOrder < Linter
    include LinterRegistry

    # Called when the linter is fired up on a document. Acts as a pseudo-constructor
    def visit_root( node )

      # get configured order
      configured_groups = get_order_from_conf

      # and map things around
      @groups = []
      @property_to_group = {}
      configured_groups.each_pair do |group, props|
        @groups.push group
        props.each do |property|
          @property_to_group[property] = group
        end
      end

      yield

    end

    # Logic that actually performs order
    def check_order( node )

      # 1. get a list of properties we can sort
      sortable_properties = node.children.select do |child|
        child.is_a? Sass::Tree::PropNode
      end

      # 2. group things
      grouped_properties = {}
      props = sortable_properties.map do |prop|

        # clean the name
        name = prop.name.join.gsub(/^(-\w+(-osx)?-)?/, '')
        name_splat = name.gsub(/-.*$/, '*')

        # if there’s no group, move on
        next unless @property_to_group.key? name or @property_to_group.key? name_splat
        group = @property_to_group[name] || @property_to_group[name_splat]

        # if there’s no existing group
        unless grouped_properties.key? group
          grouped_properties[group] = { first: 1.0/0, last: 0, props: [] }
        end

        # build a concat
        concat = { name: name, node: prop, group: group, line: prop.line }

        # drop things on
        grouped_properties[group][:first] = [grouped_properties[group][:first], prop.line].min
        grouped_properties[group][:last]  = [grouped_properties[group][:last],  prop.line].max
        grouped_properties[group][:props] << concat

        concat

      end
      props.compact!

      # 3. call down
      unless grouped_properties.empty?
        check_sort_order props, grouped_properties
      end

      # 4. yield so we can process children
      yield

    end

    # alias things out
    alias visit_media check_order
    alias visit_mixin check_order
    alias visit_rule  check_order
    alias visit_prop  check_order

    def visit_if(node, &block)
      check_order(node, &block)
      visit(node.else) if node.else
    end

    private

      def get_order_from_conf
        case config['order']
          when Array
          when Hash
            config['order']
          else
            raise SCSSLint::Exceptions::LinterError, 'No property sort order specified!'
        end

      end

      def check_sort_order( props, grouped )

        # get stats on grouped version
        grouped.each_value do |group|

          # number of properties
          group[:num]   = group[:props].length
          group[:delta] = group[:last] - group[:first]

        end

        # quick duck-type
        # TODO: proper sense-checking
        quick_check_order props

        # if we’re checking whitespace, do so
        check_whitespace( grouped ) unless config['space_between_groups'].nil? or !config['space_between_groups'] or grouped.length < 2

        return

      end

      def quick_check_order( props )

        current_group = 0
        good = true

        props.each do |prop|

          # if it’s the current group, move on
          next if prop[:group] == @groups[current_group]

          # find an index
          idx = @groups.index prop[:group]

          # if it’s less-than, error out
          if idx < current_group
            # @TODO: remove in lieu of proper checking
            add_lint prop[:node], "Found property ‘#{prop[:name]}’ in group ‘#{@groups[current_group]}’ (should be in ‘#{prop[:group]}’)"
            good = false
          else
            current_group = idx
          end

        end

        good

      end

      def check_whitespace( grouped )

        # get a maximum limit
        limit = config['min_group_size'] || 3

        # for all after the first group
        previous = nil
        @groups.each do |group|

          # if we don’t know about it, bail
          next unless grouped.key? group

          # set current
          current = grouped[group]

          # if we don’t have previous…
          (previous = current and next) if previous.nil?

          # if there are fewer than the limit in this group, bounce
          next if current[:props].length < limit

          # look for some space
          unless ((current[:first] - previous[:last]) >= 2)
            add_lint current[:props].first[:node], "Must be at least one empty line above ‘#{current[:props].first[:name]}’"
          end

          # set previous
          previous = current

        end

    end
  end
end
