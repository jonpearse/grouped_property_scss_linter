module SCSSLint
  class Linter::GroupedPropertyOrder < Linter
    include LinterRegistry

    # Called when the linter is fired up on a document. Acts as a pseudo-constructor
    def visit_root( node )

      # get configured order
      @configured_groups = get_order_from_conf

      # and map things around
      @groups = []
      @property_to_group = {}
      @configured_groups.each_pair do |name, group|
        @groups.push name
        group['properties'].each do |property|
          @property_to_group[property] = name
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

        # simplify the name a little
        name = prop.name.join

        # attempt to match the name
        group = find_match_for_property name

        # if it didn’t find anything, move on
        next if group.nil?

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

      # Acquires configuration and populates out a group array
      def get_order_from_conf

        # 1. acquire defaults + default them, just in case
        defaults = config['defaults']
        defaults['space_around'] |= true
        defaults['max_no_space'] = 3

        # 2. acquire groups
        groups = config['groups']

        # 3. munge
        groups.each_pair do |name, group|

          # a. if it’s an array, cast it
          group = { 'properties' => group } if group.is_a? Array

          # b. merge in some defaults
          group['space_around'] = defaults['space_around'] if group['space_around'].nil?
          group['max_no_space'] ||= defaults['max_no_space']

        end

        groups

      end

      # Finds a matching group for a specified property
      def find_match_for_property( prop )

        # sanitise the name by removing any browser prefixes
        prop = prop.gsub(/^(-\w+(-osx)?-)?/, '')

        # iteratively remove hyphens from the property…
        while prop =~ /\-/

          # if we know about this property or its splatted variety…
          if @property_to_group.key? prop or @property_to_group.key? prop+'*'

            return @property_to_group[prop] || @property_to_group[prop+'*']

          end

          prop.gsub! /\-(\w+)$/, ''

        end

        # finally…
        if @property_to_group.key? prop or @property_to_group.key? prop+'*'

          return @property_to_group[prop] || @property_to_group[prop+'*']

        end

        nil

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
        check_whitespace( grouped ) unless grouped.length < 2

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

        # get a quick handle on all the groups we’ve found
        detected_groups = grouped.keys

        # iterate through
        curr_idx = 0
        grouped.each_pair do |name, current|

          # get a configuration
          group_conf = @configured_groups[name]

          # if we don’t care about space, bail
          (curr_idx += 1 and next) unless group_conf['space_around']

          # similarly, if this group is too small to trigger spacing, bounce
          (curr_idx += 1 and next)unless current[:props].length > group_conf['max_no_space']

          # set some easy references
          next_group = detected_groups.length > curr_idx ? grouped[detected_groups[curr_idx + 1]] : nil
          prev_group = curr_idx > 0 ? grouped[detected_groups[curr_idx - 1]] : nil

          # if there’s something after us, and there’s no space
          if !next_group.nil? and ((next_group[:first] - current[:last]) < 2)

            # raise a lint error
            add_lint current[:props].last[:node], "Must be at least one empty line after ‘#{current[:props].last[:name]}’"

            # also, flag the next group so we don’t catch it next time ‘round
            next_group[:raised] = true
          end

          # if there’s something before us, and there’s no space…
          if !prev_group.nil? and ((current[:first] - prev_group[:last]) < 2) and current[:raised].nil?

            # raise a lint error
            add_lint current[:props].first[:node], "Must be at least one empty line before ‘#{current[:props].first[:name]}’"

          end

          # finally, increment
          curr_idx += 1

        end
    end
  end
end
