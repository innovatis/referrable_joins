path = File.join(File.dirname(__FILE__), 'referrable_joins')
$:.unshift(path) unless $:.include?(path)

require 'referrable_joins/active_record_hacks'

