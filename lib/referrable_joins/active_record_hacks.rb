module ActiveRecord

  class Base
    class << self
      delegate :outer_joins, :inner_joins, :to => :scoped
    end 
  end 

  module QueryMethods
    
    attr_accessor :outer_joins_values, :inner_joins_values

    def joins(*args)
      relation = clone

      args.flatten!
      relation.inner_joins_values ||= []
      relation.inner_joins_values += args unless args.blank?

      relation
    end
    alias_method :inner_joins, :joins
    
    def outer_joins(*args)
      relation = clone

      args.flatten!
      relation.outer_joins_values ||= []
      relation.outer_joins_values += args unless args.blank?

      relation
    end

    def build_arel
      arel = table
      
      @inner_joins_values||=[]
      @outer_joins_values||=[]
      
      arel = build_joins(arel, @inner_joins_values, @outer_joins_values) unless @outer_joins_values.blank? && @inner_joins_values.blank?

      (@where_values - ['']).uniq.each do |where|
        where = Arel.sql(where) if String === where
        arel = arel.where(Arel::Nodes::Grouping.new(where))
      end

      arel = arel.having(*@having_values.uniq.reject{|h| h.blank?}) unless @having_values.empty?

      arel = arel.take(@limit_value) if @limit_value
      arel = arel.skip(@offset_value) if @offset_value

      arel = arel.group(*@group_values.uniq.reject{|g| g.blank?}) unless @group_values.empty?

      arel = arel.order(*@order_values.uniq.reject{|o| o.blank?}) unless @order_values.empty?

      arel = build_select(arel, @select_values.uniq)

      arel = arel.from(@from_value) if @from_value
      arel = arel.lock(@lock_value) if @lock_value

      arel
    end

    
    def build_joins(relation, inner_joins, outer_joins)
      inner_association_joins = []
      outer_association_joins = []

      inner_joins = @inner_joins_values.map {|j| j.respond_to?(:strip) ? j.strip : j}.uniq
      outer_joins  =  @outer_joins_values.map {|j| j.respond_to?(:strip) ? j.strip : j}.uniq

      inner_joins.each do |join|
        inner_association_joins << join if [Hash, Array, Symbol, ReferrableJoin].include?(join.class) && !array_of_strings?(join)
      end

      outer_joins.each do |join|
        outer_association_joins << join if [Hash, Array, Symbol, ReferrableJoin].include?(join.class) && !array_of_strings?(join)
      end

      stashed_association_joins = (inner_joins + outer_joins).grep(ActiveRecord::Associations::ClassMethods::JoinDependency::JoinAssociation)

      non_association_joins = (outer_joins + inner_joins - outer_association_joins - inner_association_joins - stashed_association_joins)
      custom_joins = custom_join_sql(*non_association_joins)

      join_dependency = ActiveRecord::Associations::ClassMethods::JoinDependency.new(@klass, inner_association_joins, outer_association_joins, custom_joins)

      join_dependency.graft(*stashed_association_joins)

      @implicit_readonly = true unless inner_association_joins.empty? && outer_association_joins.empty? && stashed_association_joins.empty?

      to_join = []

      join_dependency.join_associations.each do |association|
        if (association_relation = association.relation).is_a?(Array)
          to_join << [association_relation.first, association.join_type, association.association_join.first]
          to_join << [association_relation.last, association.join_type, association.association_join.last]
        else
          to_join << [association_relation, association.join_type, association.association_join]
        end
      end

      to_join.uniq.each do |left, join_type, right|
        relation = relation.join(left, join_type).on(*right)
      end

      relation.join(custom_joins)
    end
    
  end 
  
  
  module Associations
    module ClassMethods
      class JoinDependency

        def initialize(base, inner_associations, outer_associations, joins)
          @joins                 = [JoinBase.new(base, joins)]
          @associations          = {}
          @reflections           = []
          @base_records_hash     = {}
          @base_records_in_order = []
          @table_aliases         = Hash.new { |aliases, table| aliases[table] = 0 }
          @table_aliases[base.table_name] = 1
          build(inner_associations, @joins.first, Arel::InnerJoin)
          build(outer_associations, @joins.first, Arel::OuterJoin)
        end
    
        def build(associations, parent = nil, join_type = Arel::InnerJoin)
          parent ||= @joins.last
          case associations
          # MONKEYPATCH Added ReferrableJoin here
          when Symbol, String, ReferrableJoin
            reflection = parent.reflections[associations.to_s.intern] or
              raise ConfigurationError, "Association named '#{ associations }' was not found; perhaps you misspelled it\?"
            unless join_association = find_join_association(reflection, parent)
              @reflections << reflection
              join_association = build_join_association(reflection, parent)
              # <MONKEYPATCH added this conditional
              if associations.kind_of?(ReferrableJoin)
                associations.mirror_relation(join_association.relation)
              end 
              # >MONKEYPATCH
              join_association.join_type = join_type
              @joins << join_association
              cache_joined_association(join_association)
            end
            join_association
          when Array
            associations.each do |association|
              build(association, parent, join_type)
            end
          when Hash
            associations.keys.sort{|a,b|a.to_s<=>b.to_s}.each do |name|
              join_association = build(name, parent, join_type)
              build(associations[name], join_association, join_type)
            end
          else
            raise ConfigurationError, associations.inspect
          end
        end
      end 
    end 
  end 
end 
