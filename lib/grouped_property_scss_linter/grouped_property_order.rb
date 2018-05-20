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
      count = 0
      @configured_groups.each_pair do |name, group|

        @groups <<  name
        group['properties'].each{ |property| @property_to_group[property] = { name: name, idx: count }}
        count += 1

      end

      yield

    end

    # Logic that actually performs order
    def check_order( node )

      # 1. get a list of properties we can sort
      sortable_properties = node.children.select{ |child| child.is_a?( Sass::Tree::PropNode )}

      # 2. group things
      grouped_properties = {}
      props = sortable_properties.map do |prop|

        # simplify the name a little
        name = prop.name.join

        # attempt to match the name
        group = find_match_for_property( name )

        # if it didn’t find anything, move on
        next if group.nil?

        # if there’s no existing group
        grouped_properties[group[:name]] = { first: 1.0/0, last: 0, props: [] } unless grouped_properties.key?( group[:name] )

        # build a concat
        concat = { name: name, node: prop, group: group[:name], line: prop.line, group_idx: group[:idx] }

        # drop things on
        grouped_properties[group[:name]][:first] = [grouped_properties[group[:name]][:first], prop.line].min
        grouped_properties[group[:name]][:last]  = [grouped_properties[group[:name]][:last],  prop.line].max
        grouped_properties[group[:name]][:props] << concat

        concat

      end
      props.compact!

      # 3. call down
      check_sort_order( props, grouped_properties ) unless grouped_properties.empty?

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
        defaults['space_around']     |= true
        defaults['max_no_space']     |= 3

        # 2, acquire groups
        groups = config['groups'] || load_groups_from_style

        # 3. if it failed, bail
        raise 'No groups configured' if groups.nil?

        # 4. if we’re worrying about CSS variables
        if config['css_variables_first']

          groups = {
            'css_vars' => {
              'properties' => [ '{VARIABLE}' ],
              'space_around' => true,
              'max_no_space' => 0
            }
          }.merge( groups )

        end

        # 5. munge
        groups.update( groups ) do |name, group|

          # a. if it’s an array, cast it
          group = { 'properties' => group } if group.is_a?( Array )

          # b. merge in some defaults
          group['space_around'] = defaults['space_around'] if group['space_around'].nil?
          group['max_no_space'] ||= defaults['max_no_space']

          # c. return
          group

        end

        groups

      end

      # Loads a group from a configured style
      def load_groups_from_style

        # 0. if the style is blank/empty…
        ( raise 'No style specified' and return ) if config['style'].empty?

        # 1. attempt to find the file
        data_filename = File.join( GroupedPropertyScssLinter::STYLES_DIR, "#{config['style']}.yaml" )

        # 2. does it exist
        ( raise "No style ‘#{config['style']}’ found" and return ) unless File.exists?( data_filename )

        # 3. can we read it
        ( raise "Cannot read style ‘#{config['style']}’" and return ) unless File.readable?( data_filename )

        # 4. open
        style_config = YAML.load_file( data_filename )

        # 5. barf?
        ( raise "Bad style file found for ‘#{config['style']}’" and return ) if ( style_config.nil? or style_config['groups'].nil? )

        style_config['groups']
      end

      # Finds a matching group for a specified property
      def find_match_for_property( prop )

        # if it’s a property
        prop = '{VARIABLE}' if ( prop.start_with?( '--' ))

        # sanitise the name by removing any browser prefixes
        prop = prop.gsub( /^(-\w+(-osx)?-)?/, '' )

        # iteratively remove hyphens from the property…
        while prop =~ /\-/

          # if we know about this property or its splatted variety…
          if @property_to_group.key? prop or @property_to_group.key? prop+'*'

            return ( @property_to_group[prop] || @property_to_group[prop+'*'] )

          end

          # strip the leading hyphen and try again
          prop.gsub!( /\-(\w+)$/, '' )

        end

        # finally…
        if @property_to_group.key? prop or @property_to_group.key? prop+'*'

          return ( @property_to_group[prop] || @property_to_group[prop+'*'] )

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
        quick_check_order( props, grouped )

        # if we’re checking whitespace, do so
        check_whitespace( grouped ) unless grouped.length < 2

      end

      def quick_check_order( props, grouped )

        current_group = 0
        good = true

        props.each do |prop|

          # if it’s the current group, move on
          next if prop[:group] == @groups[current_group]

          # find an index
          idx = @groups.index( prop[:group] )

          # if it’s less-than, error out
          if idx < current_group

            if prop[:name].start_with?( '--' )

              add_lint( prop[:node], "CSS variables should be defined at the beginning of the rule (found #{prop[:name].bold})")

            else

              ext = config['extended_hinting'] ? " (assigned group ‘#{prop[:group].bold}’, found group ‘#{@groups[current_group].bold}’)" : ""

              add_lint( prop[:node], "property ‘#{prop[:name].bold}’ should be #{hint_text_for(prop, grouped, props)}#{ext}" )

            end
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
          ( curr_idx += 1 and next ) unless group_conf['space_around']

          # similarly, if this group is too small to trigger spacing, bounce
          ( curr_idx += 1 and next ) unless current[:props].length > group_conf['max_no_space']

          # set some easy references
          next_group = detected_groups.length > curr_idx ? grouped[detected_groups[curr_idx + 1]] : nil
          prev_group = curr_idx > 0 ? grouped[detected_groups[curr_idx - 1]] : nil

          # if there’s something after us, and there’s no space
          if !next_group.nil? and ((next_group[:first] - current[:last]) < 2)

            # raise a lint error
            add_lint( current[:props].last[:node], "Must be at least one empty line after ‘#{current[:props].last[:name]}’" )

            # also, flag the next group so we don’t catch it next time ‘round
            next_group[:raised] = true

          end

          # if there’s something before us, and there’s no space…
          if !prev_group.nil? and ((current[:first] - prev_group[:last]) < 2) and current[:raised].nil?

            # raise a lint error
            add_lint( current[:props].first[:node], "Must be at least one empty line before ‘#{current[:props].first[:name]}’" )

          end

          # finally, increment
          curr_idx += 1

        end
      end

      def hint_text_for( prop, grouped_props, context )

        # get target group
        dst_group = prop[:group]

        # if we know about the group…
        if grouped_props.key?( dst_group )

          # get the first property of the current group
          dst_prop = grouped_props[dst_group][:props].first

          # if it’s a different property, return
          return "after ‘#{dst_prop[:name].bold}’" if dst_prop != prop

        end

        # either our offending property is the sole member of a group, or it’s very lost… so look for a previous marker
        curr_idx = prop[:group_idx]
        while curr_idx > 0

          # decrement and reset
          curr_idx  = curr_idx - 1
          dst_group = @groups[curr_idx]

          # look
          if grouped_props.key? dst_group

            # get the _last_ property of the group
            dst_prop = grouped_props[dst_group][:props].last

            # and return
            return "after ‘#{dst_prop[:name].bold}’"

          end
        end

        # otherwise, it probably belongs right at the start
        "before ‘#{context.first[:name].bold}’"

      end
  end
end
