#!/usr/bin/env ruby
#  Phusion Passenger - http://www.modrails.com/
#  Copyright (C) 2008  Phusion
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; version 2 of the License.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License along
#  with this program; if not, write to the Free Software Foundation, Inc.,
#  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
##############################################################################
# A script for finding owner pipe leaks in Apache. An owner pipe is considered
# to be leaked if it is owned by two or more Apache processes.
#
# This script only works on Linux. Only run it when Apache is idle.

$LOAD_PATH << "#{File.dirname(__FILE__)}/../lib"
require 'set'
require 'passenger/platform_info'

include PlatformInfo

def list_pids
	Dir.chdir("/proc") do
		return Dir["*"].select do |x|
			x =~ /^\d+$/
		end
	end
end

def list_pipes(pid)
	pipes = []
	Dir["/proc/#{pid}/fd/*"].each do |file|
		if File.symlink?(file) && File.readlink(file) =~ /^pipe:\[(.*)\]$/
			pipes << $1
		end
	end
	return pipes
end

def is_rails_app(pid)
	return File.read("/proc/#{pid}/cmdline") =~ /^Rails: /
end

def is_apache(pid)
	begin
		return File.readlink("/proc/#{pid}/exe") == HTTPD
	rescue
		return false
	end
end

# Returns a pair of these items:
# - The owner pipe map. Maps a Rails application's PID to to its owner pipe's ID.
# - The reverse map. Maps an owner pipe ID to the Rail application's PID.
def create_owner_pipe_map
	map = {}
	reverse_map = {}
	list_pids.select{ |x| is_rails_app(x) }.each do |pid|
		owner_pipe = list_pipes(pid).first
		map[pid] = owner_pipe
		reverse_map[owner_pipe] = pid
	end
	return [map, reverse_map]
end

def show_owner_pipe_listing(map, reverse_map)
	puts "------------ Owner pipe listing ------------"
	count = 0
	list_pids.select{ |x| is_apache(x) }.sort.each do |pid|
		list_pipes(pid).select do |pipe|
			reverse_map.has_key?(pipe)
		end.each do |pipe|
			puts "Apache PID #{pid} holds the owner pipe (#{pipe}) " <<
				"for Rails PID #{reverse_map[pipe]}"
			count += 1
		end
	end
	if count == 0
		puts "(none)"
	end
	puts ""
end

def show_owner_pipe_leaks(map, reverse_map)
	apache_owner_pipe_map = {}
	list_pids.select{ |x| is_apache(x) }.sort.each do |pid|
		list_pipes(pid).select do |pipe|
			reverse_map.has_key?(pipe)
		end.each do |pipe|
			apache_owner_pipe_map[pipe] ||= []
			apache_owner_pipe_map[pipe] << pid
		end
	end
	
	puts "------------ Leaks ------------"
	count = 0
	apache_owner_pipe_map.each_pair do |pipe, pids|
		if pids.size >= 2
			puts "Rails PID #{reverse_map[pipe]} owned by Apache processes: #{pids.join(", ")}"
			count += 1
		end
	end
	if count == 0
		puts "(none)"
	end
end

def start
	map, reverse_map = create_owner_pipe_map
	show_owner_pipe_listing(map, reverse_map)
	show_owner_pipe_leaks(map, reverse_map)
end

start
