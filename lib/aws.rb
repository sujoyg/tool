# Using REXML since it was hard to make libxml work with namespaces in AWS XML responses.
require "guid"
require "rexml/document"

class AWSError < Exception
end

class UserError < Exception
end

class AWS
  def initialize(constants)
    @constants = constants

    root = File.expand_path("../..", __FILE__)
    @rds = File.join root, "vendor/RDSCli-1.3.003/bin"

    ENV["AWS_RDS_HOME"] = File.join root, "vendor/RDSCli-1.3.003"
    if ENV["JAVA_HOME"].nil? || ENV["JAVA_HOME"].size == 0
       ENV["JAVA_HOME"] = if File.exists? "/usr/libexec/java_home"
       			    `/usr/libexec/java_home`.strip
                       	  else
		            # There are two levels of indirection on Ubuntu boxes.
                            File.dirname File.dirname `readlink -e \`which java\``.strip
                       	  end
    end

    @tool_dir = ENV["TOOL_DIR"] || File.join(ENV["HOME"], ".tool")
    raise UserError.new("Please create a directory #{@tool_dir} with your AWS private key and cert files or set TOOL_AWS_CONFIG to an existing directory.") unless File.exists? @tool_dir
    raise UserError.new("AWS key file not found in directory #{@tool_dir} or its prefix is not pk.") unless Dir[File.join @tool_dir, "pk-*"].size > 0
    raise UserError.new("AWS cert file not found in directory #{@tool_dir} or its prefix is not cert.") unless Dir[File.join @tool_dir, "cert-*"].size > 0

    ENV["EC2_PRIVATE_KEY"] = Dir[File.join @tool_dir, "pk-*"][0]
    ENV["EC2_CERT"] = Dir[File.join @tool_dir, "cert-*"][0]
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
    elsif args[0] == "clone"
      aws_database_clone(args[1..-1])
    elsif args[0] == "delete"
      aws_database_delete(args[1..-1])
    elsif args[0] == "list"
      aws_database_list(args[1..-1])
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
      puts "\t#{$script} aws database pull ..."
      puts "\t#{$script} aws database push ..."
      puts "\t#{$script} aws database status ..."
    end
  end

  def aws_database_connect(args)
    options = {}
    command_line_parser = OptionParser.new do |config|
      config.banner = "Usage: aws database connect <INSTANCE>"

      config.on("-d", "--database DATABASE", "Database name.") do |database|
        options[:database] = database
      end

      config.on("-u", "--user USER", "Database user.") do |user|
        options[:user] = user
      end

      config.on("-p", "--password PASSWORD", "Database password.") do |password|
        options[:password] = password
      end
    end

    command_line_parser.parse!(args)
    if args.size < 1
      puts command_line_parser
      exit
    end

    instance = args[0]
    user = options[:user] || @constants.database && @constants.database.user
    password = options[:password] || @constants.database && @constants.database.password
    database = options[:database]

    raise UserError.new("Please specify a user on the command line or in #{@tool_dir}/constants.yml") if user.nil?
    # If password is not specified, mysql client will prompt for one.

    begin
      address = get_database_instance_address(instance)
    rescue AWSError => e
      puts "Error: #{parse_aws_error(e.to_s)}"
      return
    end

    if database.nil?
      exec "mysql --prompt '\\h(\\u)>' -u#{user} -p#{password} -h#{address}"
    else
      exec "mysql --prompt '\\h(\\u)>' -u#{user} -p#{password} -h#{address} #{database}"
    end
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

      config.on("--admin_user USER", "Admin user.") do |user|
        options[:admin_user] = user
      end

      config.on("--admin_password PASSWORD", "Admin password.") do |password|
        options[:admin_password] = password
      end

      config.on("--user USER", "This user will be granted all privileges to the database.") do |user|
        options[:user] = user
      end

      config.on("--password PASSWORD", "Password for the user.") do |password|
        options[:password] = password
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

    admin_user = options[:admin_user]
    admin_password = options[:admin_password]
    raise UserError.new("Please specify an admin user with --admin_user.") if admin_user.nil?
    raise UserError.new("Please specify an admin password with --admin_password.") if admin_password.nil?

    user = options[:user]
    password = options[:password]

    begin
      host = get_database_instance_address(instance)
      databases = get_databases(host, admin_user, admin_password)
      if databases.include? database
        puts "Instance and database already exists."
      else
        puts "Instance already exists."
        puts "Creating database #{database}."
        `mysql -h#{host} -u#{admin_user} -p#{admin_password} -e "CREATE DATABASE #{database}"`
        `mysql -h#{host} -u#{admin_user} -p#{admin_password} -e "ALTER database #{database} CHARACTER SET utf8 COLLATE utf8_general_ci"`
        unless user.nil?
          if password.nil?
            `mysql -h#{host} -u#{admin_user} -p#{admin_password} -e "GRANT ALL PRIVILEGES ON #{database}.* TO '#{user}'@'%'"`
          else
            `mysql -h#{host} -u#{admin_user} -p#{admin_password} -e "GRANT ALL PRIVILEGES ON #{database}.* TO '#{user}'@'%' IDENTIFIED BY '#{password}'"`
          end
        end
      end
    rescue AWSError => e
      create_database_instance(instance, storage, size, admin_user, admin_password, database, multi_az)
    end
  end


  def aws_database_clone(args)
    STDOUT.sync = true

    options = {}
    command_line_parser = OptionParser.new do |config|
      config.banner = "Usage: aws database clone <SOURCE_INSTANCE>:<SOURCE_DATABASE> <TARGET_INSTANCE>:<TARGET_DATABASE> [options]"

      config.on("-u", "--user USER", "Database user.") do |user|
        options[:user] = user
      end

      config.on("-p", "--password PASSWORD", "Database password.") do |password|
        options[:password] = password
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

    source, target = args

    user = options[:user] || @constants.database && @constants.database.user
    password = options[:password] || @constants.database && @constants.database.user

    source_instance, source_database = source.split(":", 2)
    raise UserError.new("Please specify a source RDS instance.") if source_instance.nil?
    raise UserError.new("Please specify a source database.") if source_database.nil?

    target_instance, target_database = target.split(":", 2)
    raise UserError.new("Please specify a target RDS instance.") if target_instance.nil?
    raise UserError.new("Please specify a target database.") if target_database.nil?
    raise UserError.new("Source and target cannot be the same.") if source_instance == target_instance and source_database == target_database

    raise UserError.new("Please specify a user on the command line or in #{@tool_dir}/constants.yml") if user.nil?
    # If password is not specified, mysql client will prompt for one.

    # TODO: A way to check that the provided user and password work for local and remote databases.

    begin
      source_address = get_database_instance_address(source_instance)
      target_address = get_database_instance_address(target_instance)
    rescue AWSError => e
      puts "Error: #{parse_aws_error(e.to_s)}"
      return
    end

    tables = `mysql -u#{user} -p#{password} -h#{source_address} #{source_database} -N -e "SHOW TABLES"`.split
    puts "#{tables.size} tables found."
    tmpfile = File.join "/tmp", Guid.new.to_s
    tables.each do |table|
      puts "Cloning #{table}"
      `mysqldump -u#{user} -p#{password} -h#{source_address} #{source_database} #{table} > #{tmpfile}`
      `mysql -u#{user} -p#{password} -h#{target_address} #{target_database} < #{tmpfile}`
    end
    nil
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


  def aws_database_list(args)
    options = {}
    command_line_parser = OptionParser.new do |config|
      config.banner = "Usage: aws database list"

      config.on("-u", "--user USER", "Database user.") do |user|
        options[:user] = user
      end

      config.on("-p", "--password PASSWORD", "Database password.") do |password|
        options[:password] = password
      end

      config.on("-h", "--help", "Display this help message") do
        puts config
        exit
      end
    end

    command_line_parser.parse!(args)

    command = "#{@rds}/rds-describe-db-instances --show-xml"

    output = `#{command}`
    if $?.to_i != 0
      raise AWSError.new(output)
    end

    doc = REXML::Document.new output
    doc.elements.each("DescribeDBInstancesResponse/DescribeDBInstancesResult/DBInstances/DBInstance") do |element|
      instance = element.elements["DBInstanceIdentifier"].text
      host = element.elements["Endpoint/Address"].text
      admin = options[:user] || element.elements["MasterUsername"].text
      password = options[:password]

      databases = `mysql -h#{host} -u#{admin} -p#{password} -N -e "SHOW DATABASES"`.split

      puts "Instance: #{instance}"
      puts "Endpoint: #{host}"
      puts "Databases:"
      databases.each { |database| puts "\t#{database}" }
    end

    return
  end


  def aws_database_pull(args)
    options = {}
    command_line_parser = OptionParser.new do |config|
      config.banner = "Usage: aws database pull <INSTANCE> <REMOTE DATABASE> <LOCAL DATABASE> <TABLE> [options]"

      config.on("-u", "--user USER", "Database user.") do |user|
        options[:user] = user
      end

      config.on("-p", "--password PASSWORD", "Database password.") do |password|
        options[:password] = password
      end

      config.on("-U", "--local_user USER", "Local database user.") do |user|
        options[:local_user] = user
      end

      config.on("-P", "--local_password PASSWORD", "Local database password.") do |password|
        options[:local_password] = password
      end

      config.on("-h", "--help", "Display this help message") do
        puts config
        exit
      end
    end

    command_line_parser.parse!(args)
    if args.size != 4
      puts command_line_parser
      exit
    end

    instance, source_database, target_database, table = args

    user = options[:user] || @constants.database && @constants.database.user
    password = options[:password] || @constants.database && @constants.database.password
    local_user = options[:local_user] || @constants.database && @constants.database.local_user
    local_password = options[:local_password] || @constants.database && @constants.database.local_password

    raise UserError.new("Please specify a user on the command line or in #{@tool_dir}/constants.yml") if user.nil?
    # If password is not specified, mysql client will prompt for one.

    begin
      address = get_database_instance_address(instance)
    rescue AWSError => e
      puts "Error: #{parse_aws_error(e.to_s)}"
      return
    end

    params = []
    params << "-u #{local_user}" unless local_user.nil?
    params << "-p #{local_password}" unless local_password.nil?

    exec "mysqldump -u#{user} -p#{password} -h#{address} #{source_database} #{table} | mysql #{params.join(' ')} #{target_database}"
  end


  def aws_database_push(args)
    options = {}
    command_line_parser = OptionParser.new do |config|
      config.banner = "Usage: aws database push <LOCAL DATABASE> <INSTANCE>:<REMOTE DATABASE> <TABLE> [options]"

      config.on("-u", "--user USER", "Remote database user.") do |user|
        options[:remote_user] = user
      end

      config.on("-p", "--password PASSWORD", "Remote database password.") do |password|
        options[:remote_password] = password
      end

      config.on("-U", "--local_user USER", "Local database user.") do |user|
        options[:local_user] = user
      end

      config.on("-P", "--local_password PASSWORD", "Local database password.") do |password|
        options[:local_password] = password
      end

      config.on("-h", "--help", "Display this help message") do
        puts config
        exit
      end
    end

    command_line_parser.parse!(args)
    if args.size != 3
      puts command_line_parser
      exit
    end

    source_database, target, table = args
    instance, target_database = target.split(":", 2)
    raise UserError.new("Please specify an RDS instance.") if instance.nil?
    raise UserError.new("Please specify an target database.") if target_database.nil?

    remote_user = options[:remote_user] || @constants.database && @constants.database.user
    remote_password = options[:remote_password] || @constants.database && @constants.database.password
    raise UserError.new("Please specify a remote user on the command line or in #{@tool_dir}/constants.yml") if remote_user.nil?
    # If password is not specified, mysql client will prompt for one.

    local_user = options[:local_user] || @constants.database && @constants.database.local_user
    local_password = options[:local_password] || @constants.database && @constants.database.local_password
    # A local user or password is not required.

    # TODO: A way to check that the provided user and password work for local and remote databases.

    begin
      address = get_database_instance_address(instance)
    rescue AWSError => e
      puts "Error: #{parse_aws_error(e.to_s)}"
      return
    end

    local_params = []
    local_params << "-u#{local_user}" if local_user
    local_params << "-p#{local_password}" if local_password
    exec "mysqldump #{local_params.join(" ")} #{source_database} #{table} | mysql -u#{remote_user} -p#{remote_password} -h#{address} #{target_database}"
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
    status = doc.elements["DescribeDBInstancesResponse/DescribeDBInstancesResult/DBInstances/DBInstance"].elements["DBInstanceStatus"].text

    return status
  end

  def get_database_instance_address(instance)
    command = "#{@rds}/rds-describe-db-instances #{instance} --show-xml"

    output = `#{command}`
    if $?.to_i != 0
      raise AWSError.new(output)
    end

    doc = REXML::Document.new output
    address = doc.elements["DescribeDBInstancesResponse/DescribeDBInstancesResult/DBInstances/DBInstance"].elements["Endpoint/Address"].text

    return address
  end

  def parse_aws_error(error)
    error = error.to_s
    error.gsub!('aws:', '') # REXML on Ruby 1.8.7 barfs on elements like <aws:RequestId>.
    doc = REXML::Document.new error
    puts error
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


  private

  def create_database_instance(instance, storage, size, admin_user, admin_password, database, multi_az)
    command = <<-COMMAND
      #{@rds}/rds-create-db-instance #{instance} \\
	      -s #{storage} -c #{size} -e MySQL5.1 -u #{admin_user} -p #{admin_password} \\
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

    host = get_database_instance_address(instance)
    check_database_connection(host, user, password)
  end

  def check_database_connection(host, user, password)
    print "\nAttempting to connect to the instance ... "

    output = `echo "select 1;" | mysql -h#{host} -u#{user} -p#{password} 2>&1`
    if $?.to_i == 0
      print "OK\n"
    else
      print "Failed\n"
      print output
    end
  end

  def get_databases(host, user, password)
    `mysql -h#{host} -u#{user} -p#{password} -N -e "SHOW DATABASES"`.split.map(&:strip)
  end
end
