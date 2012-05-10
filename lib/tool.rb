# Using REXML since it was hard to make libxml work with namespaces in AWS XML responses.
require "rexml/document"

class AWSError < Exception
end

class AWS
  def initialize
    root = File.expand_path("../..", __FILE__)
    @rds = File.join root, "vendor/RDSCli-1.3.003/bin"

    ENV["AWS_RDS_HOME"] = File.join root, "vendor/RDSCli-1.3.003"
    ENV["JAVA_HOME"] = if File.exists? "/usr/libexec/java_home"
      `/usr/libexec/java_home`.strip
    else
      File.dirname File.dirname `readlink \`which java\``.strip
    end

    tool_dir = ENV["TOOL_AWS_CONFIG"] || File.join(ENV["HOME"], ".tool")
    raise "Please create a directory #{tool_dir} with your AWS private key and cert files or set TOOL_AWS_CONFIG to an existing directory." unless Dir.exists? tool_dir
    raise "AWS key file not found in directory #{tool_dir} or its prefix is not pk." unless Dir[File.join tool_dir, "pk-*"].size > 0
    raise "AWS cert file not found in directory #{tool_dir} or its prefix is not cert." unless Dir[File.join tool_dir, "cert-*"].size > 0

    ENV["EC2_PRIVATE_KEY"] = Dir[File.join tool_dir, "pk-*"][0]
    ENV["EC2_CERT"] = Dir[File.join tool_dir, "cert-*"][0]
  end

  def aws(args)
    if args[0] == "database"
      aws_database(args[1..-1])
    elsif args[0] == "instance"
      aws_instance(args[1..-1])
    elsif args[0] == "role"
      aws_role(args[1..-1])
    else
      puts "Usage:"
      puts "\t#{$script} aws database ..."
      puts "\t#{$script} aws instance ..."
      puts "\t#{$script} aws role ..."
    end
  end

  def aws_database(args)
    if args[0] == "connect"
      aws_database_connect(args[1..-1])
    elsif args[0] == "create"
      aws_database_create(args[1..-1])
    elsif args[0] == "delete"
      aws_database_delete(args[1..-1])
    elsif args[0] == "prepare"
      aws_database_prepare(args[1..-1])
    elsif args[0] == "pull"
      aws_database_pull(args[1..-1])
    elsif args[0] == "push"
      aws_database_push(args[1..-1])
    elsif args[0] == "status"
      aws_database_status(args[1..-1])
    else
      puts "Usage:"
      puts "\t#{$script} aws database connect ..."
      puts "\t#{$script} aws database create ..."
      puts "\t#{$script} aws database delete ..."
      puts "\t#{$script} aws database prepare ..."
      puts "\t#{$script} aws database pull ..."
      puts "\t#{$script} aws database push ..."
      puts "\t#{$script} aws database status ..."
    end
  end

  def aws_database_connect(args)
    options = {}
    command_line_parser = OptionParser.new do |config|
      config.banner = "Usage: aws database connect <INSTANCE> <DATABASE>"

      options[:user] = "dbreader"
      config.on("-u", "--user USER", "Database user (\"dbreader\")") do |user|
        options[:user] = user
      end
    end

    command_line_parser.parse!(args)
    if args.size != 2
      puts command_line_parser
      exit
    end

    instance, database = args
    user = options[:user]

    begin
      address = get_database_instance_address(instance)
    rescue AWSError => e
      puts "Error: #{parse_aws_error(e.to_s)}"
      return
    end

    exec "mysql --prompt '\\h(\\u)>' -u#{user} -pfair5count -h#{address} #{database}"
  end

  def aws_database_create(args)
    STDOUT.sync = true

    options = {}
    command_line_parser = OptionParser.new do |config|
      config.banner = "Usage: aws database create <INSTANCE> <DATABASE> [options]"

      options[:size] = "small"
      config.on("--size SIZE", [:small, :large], "Instance size ('small')") do |size|
        options[:size] = size.to_s
      end

      options[:multi_az] = false
      config.on("--multi_az", "Enable multiple availability zones (false)") do
        options[:multi_az] = true
      end

      options[:storage] = 5
      config.on("--storage SIZE", Integer, "Storage space allocated to the database in GB (5)") do |size|
        options[:storage] = size
      end

      config.on("-h", "--help", "Display this help message") do
        puts config
        exit
      end
    end

    command_line_parser.parse!(args)
    if args.size != 2
      puts command_line_parser
      exit
    end

    instance = args[0]
    database = args[1]
    storage = options[:storage]
    size = "db.m1.#{options[:size]}"
    multi_az = options[:multi_az].to_s

    command = <<-COMMAND
      #{@rds}/rds-create-db-instance #{instance} \\
	      -s #{storage} -c #{size} -e MySQL5.1 -u dbadmin -p fair5count \\
	      --db-name #{database} -g production -m #{multi_az}
    COMMAND

    output = `#{command}`
    puts output
    return if $?.to_i != 0

    count = 0
    while true
      count = (count + 1) % 4
      spinner = ["\\", "|", "/", "-"][count]

      begin
        status = get_database_instance_status(instance)
      rescue AWSError => e
        puts "Error: #{parse_aws_error e.to_s}"
        return
      end

      break if status == "available"

      print "\r#{spinner} Waiting for database to become available. Current status is \"#{status}\"."
      sleep 0.5
    end

    puts "\rDatabase is now available."

    print "\nAttempting to connect to the database ... "

    begin
      address = get_database_instance_address(instance)
      output = `echo "select 1;" | mysql -h#{address} -udbadmin -pfair5count #{database} 2>&1`
      if $?.to_i == 0
        print "OK\n"
      else
        print "Failed\n"
        print output
        return
      end
    rescue AWSError => e
      print "Failed\n"
      puts parse_aws_error(e)

      return
    end

    create_database_users(instance, database)
  end


  def aws_database_delete(args)
    command_line_parser = OptionParser.new do |config|
      config.banner = "Usage: aws database delete <INSTANCE>"
    end

    command_line_parser.parse!(args)
    if args.size != 1
      puts command_line_parser
      exit
    end

    instance = args[0]
    command = "#{@rds}/rds-delete-db-instance #{instance} -f --skip-final-snapshot"

    output = `#{command}`
    puts output
    return if $?.to_i != 0

    STDOUT.sync = true
    count = 0
    while true
      count = (count + 1) % 4
      spinner = ["\\", "|", "/", "-"][count]

      begin
        status = get_database_instance_status(instance)
      rescue AWSError => e
        puts "\rDatabase has been deleted."
        return
      end

      print "\r#{spinner} Waiting for database to be deleted. Current status is \"#{status}\"."
      sleep 0.5
    end
  end


  def aws_database_prepare(args)
    if args.size != 2
      puts "Usage: aws database prepare <INSTANCE> <DATABASE>"
      exit
    end

    instance, database = args

    create_database_users(instance, database)
  end


  def aws_database_pull(args)
    if args.size != 4
      puts "Usage: aws database pull <INSTANCE> <REMOTE DATABASE> <LOCAL DATABASE> <TABLE>"
      exit
    end

    instance, source_database, target_database, table = args
    user = "dbuser"

    begin
      address = get_database_instance_address(instance)
    rescue AWSError => e
      puts "Error: #{parse_aws_error(e.to_s)}"
      return
    end

    exec "mysqldump -u#{user} -pfair5count -h#{address} #{source_database} #{table} | mysql -udbuser -ppassword #{target_database}"
  end


  def aws_database_push(args)
    if args.size != 4
      puts "Usage: aws database push <LOCAL DATABASE> <REMOTE INSTANCE> <REMOTE DATABASE> <TABLE>"
      exit
    end

    source_database, instance, target_database, table = args
    user = "dbuser"

    begin
      address = get_database_instance_address(instance)
    rescue AWSError => e
      puts "Error: #{parse_aws_error(e.to_s)}"
      return
    end

    exec "mysqldump -udbuser -ppassword #{source_database} #{table} | mysql -u#{user} -pfair5count -h#{address} #{target_database}"
  end


  def aws_database_status(args)
    command_line_parser = OptionParser.new do |config|
      config.banner = "Usage: aws database status <INSTANCE>"
    end

    command_line_parser.parse!(args)
    if args.size != 1
      puts command_line_parser
      exit
    end

    instance = args[0]
    begin
      puts get_database_instance_status(instance)
    rescue AWSError => e
      puts "Error: #{parse_aws_error(e.to_s)}"
    end
  end


  def get_database_instance_status(instance)
    command = "#{@rds}/rds-describe-db-instances #{instance} --show-xml"

    output = `#{command}`
    if $?.to_i != 0
      raise AWSError.new(output)
    end

    doc = REXML::Document.new output
    status = doc.elements['DescribeDBInstancesResponse/DescribeDBInstancesResult/DBInstances/DBInstance'].elements['DBInstanceStatus'].text

    return status
  end

  def get_database_instance_address(instance)
    command = "#{@rds}/rds-describe-db-instances #{instance} --show-xml"

    output = `#{command}`
    if $?.to_i != 0
      raise AWSError.new(output)
    end

    doc = REXML::Document.new output
    address = doc.elements['DescribeDBInstancesResponse/DescribeDBInstancesResult/DBInstances/DBInstance'].elements['Endpoint/Address'].text

    return address
  end

  def parse_aws_error(error)
    error = error.to_s
    error.gsub!('aws:', '') # REXML on Ruby 1.8.7 barfs on elements like <aws:RequestId>.
    doc = REXML::Document.new error
    details = doc.elements['Fault/faultstring'].text

    return details
  end


  def aws_instance(args)
    if args[0] == "hostname"
      aws_instance_hostname(args[1..-1])
    else
      puts "Usage:"
      puts "\t#{$script} aws instance hostname ..."
    end
  end

  ROLES = ["cron", "demo", "memcache", "sandbox", "scoring", "search", "www"]

  def aws_role(args)
    if args[0] == "launch"
      aws_role_launch(args[1..-1])
    else
      puts "Usage: #{$script} aws role launch ..."
    end
  end

  def aws_role_launch(args)
    if args[0] && args[1] && args[1].to_i >= 0
      role = args[0]
      count = args[1].to_i

      raise "#{role} is not a recognized role." if !ROLES.include?(role)

      puts "This is an upcoming feature. Stay tuned."
    else
      puts "Usage: #{$script} aws role launch <role> <count>"
    end
  end

  def aws_instance_hostname(args)
    if args[0]
      get_ec2_instance_hostname(args[0])
    else
      puts "Usage: #{$script} aws instance hostname <instance_name>"
    end
  end


  def get_ec2_instance_hostname(instance_name)
    instances = find_ec2_instances_matching(instance_name)
    raise "Found #{instances.size} instances with name #{instance_name}." if instances.size != 1

    instances[0][:public_dns]
  end


  def find_ec2_instances_matching(name)
    instances = []

    output = `ec2-describe-instances --filter tag:Name=#{name} --filter instance-state-name=running`
    output.split("\n").each do |line|
      tokens = line.split
      instances << {:id => tokens[1], :public_dns => tokens[3]} if tokens[0] == "INSTANCE"
    end

    instances
  end

  def create_database_users(instance, database)
    # GRANT creates a user if it does not exist. Therefore, always specify a password with the first GRANT for a user.
    # This is preferred over CREATE USER since that will fail if the user already exists.
    sql = <<-SQL
    GRANT ALL ON #{database}.* to 'dbuser'@'localhost' IDENTIFIED BY 'fair5count';
    GRANT ALL ON #{database}.* to 'dbuser'@'%' IDENTIFIED BY 'fair5count';
    GRANT SELECT, DELETE ON mysql.slow_log TO 'dbuser'@'localhost';
    GRANT SELECT, DELETE ON mysql.slow_log TO 'dbuser'@'%';

    GRANT SELECT, EXECUTE ON #{database}.* TO 'dbreader'@'localhost' IDENTIFIED BY 'fair5count';
    GRANT SELECT, EXECUTE ON #{database}.* TO 'dbreader'@'%' IDENTIFIED BY 'fair5count';
    GRANT RELOAD ON *.* TO 'dbreader'@'localhost';
    GRANT RELOAD ON *.* TO 'dbreader'@'%';
    GRANT SELECT ON mysql.slow_log TO 'dbreader'@'localhost';
    GRANT SELECT ON mysql.slow_log TO 'dbreader'@'%';
    SQL

    begin
      address = get_database_instance_address(instance)
      output = `echo "#{sql}" | mysql -h#{address} -udbadmin -pfair5count #{database} 2>&1`
      if $?.to_i == 0
        print "OK\n"
      else
        print "Failed\n"
        print output
        return
      end
    rescue AWSError => e
      print "Failed\n"
      puts parse_aws_error(e)
    end
  end
end

