#!/usr/bin/env ruby

require 'fileutils'

$debug = false
$workdir = "work"
$first="e051d19cdfba59e43b4ce67c8bce65b1e30a26d9"

def usage
  puts "Usage: #{__FILE__} <git source url> <svn target url>"
end

def get_git_revisions
  list = String.new(`git rev-list --full-history #{$first}..HEAD`)
  a = Array.new()

  list.scan(/\w+/) { |s| 
    a << s
  }

  a.reverse!
  return a # return a in the correct order already, from last to first
end

def get_log_msg sha1
  log = String.new(`git rev-list --pretty=\"format:%s%n%n%b\" -n 1 #{sha1}`)
  a = Array.new()
  a = log.split(/\n/)

  a.size.times do |i|
    a[i] = a[i+1]
  end

  a.slice! a.size

  s = a.join("\n")

  if $debug
    puts "+ Log message for commit #{sha1} is:"
    puts "---"
    puts s
    puts "---"
  end

  return s
end

NON_ASCII_PRINTABLE = /[^\x20-\x7e\s]/

def binary?(file, forbidden = NON_ASCII_PRINTABLE, size = 1024) # Heuristic, hopefully it should be good enough

  return false unless File.file? file # return if "file" is not a file

  io = File.open(file)

  while buf = io.read(size)
    if forbidden =~ buf
      io.close
      return true
    end
  end

  io.close
  return false
end


def add_and_remove_files_to_svn
  status = `svn status`
  a = status.split(/\n/)
  a.each do |s|
    parse = s.split('      ')
    if (parse[0] == '?') then
      system("svn add #{parse[1]}")
    elsif (parse[0] == '!') then
      system("svn rm #{parse[1]}")
    end
  end
end

def check_binary_files
  status = `svn status`
  a = status.split(/\n/)
  a.each do |s|
    parse = s.split('      ')
    if (parse[0] == 'A') then
      if binary? parse[1]
        system("svn propset svn:mime-type 'application/octet-stream' #{parse[1]}")
      end
    end
  end
end

if ARGV[0] == nil or ARGV[1] == nil
  usage
  exit 1
end

git_repo = ARGV[0]
svn_repo = ARGV[1]

puts
puts "******************************************"
puts "** git-to-svn.rb: a Git to SVN replayer **"
puts "******************************************"
puts
puts "To enable debug modify the source so that $debug = true (line 3)" unless $debug
puts unless $debug
puts "+ Replaying commits in git repo at #{ARGV[0]}"
puts "+ into #{ARGV[1]}"
puts

if File.exist? "#{$workdir}/.git/config"
  puts "+ The directory #{$workdir} seem to contain already a git repo. Aborting..."
  puts
  exit 1
end

puts "+ Git cloning #{git_repo}..." if $debug
system("git clone -n #{git_repo} #{$workdir}")

puts "+ SVN checkouting #{svn_repo}..." if $debug
system("svn checkout #{svn_repo} #{$workdir}")

Dir.chdir($workdir)

system("svn propset svn:ignore .git .")

revs = get_git_revisions

# replay one commit at a time
revs.size.times do |i|

  log = get_log_msg revs[i]

  begin
    file = File.new(".git/tmp-git-to-svn-log-msg.txt", "w")
    file.puts log
  ensure
    file.close
  end

#   puts revs[i]

  system("git reset --hard #{revs[i]}")
  add_and_remove_files_to_svn
  check_binary_files
  system("svn ci -F .git/tmp-git-to-svn-log-msg.txt")

  FileUtils.rm_f file.path

end



