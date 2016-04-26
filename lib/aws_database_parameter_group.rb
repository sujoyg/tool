module AWSDatabaseParameterGroup
  def aws_database_parameter_group(args)
    if args[0] == 'apply'
      aws_database_parameter_group_apply(args[1..-1])
    elsif args[0] == 'create'
      aws_database_parameter_group_create(args[1..-1])
    elsif args[0] == 'display'
      aws_database_parameter_group_display args[1..-1]
    elsif args[0] == 'modify'
      aws_database_parameter_group_modify(args[1..-1])
    else
      puts "Usage:"
      puts "\t#{$script} aws [OPTIONS] database parameter group apply ..."
      puts "\t#{$script} aws [OPTIONS] database parameter group create ..."
      puts "\t#{$script} aws [OPTIONS] database parameter group display ..."
      puts "\t#{$script} aws [OPTIONS] database parameter group modify ..."
    end
  end


  def aws_database_parameter_group_apply(args)
    command_line_parser = OptionParser.new do |config|
      config.banner = 'Usage: aws database parameter group apply <INSTANCE> <PARAMETER GROUP> [options]'

      config.on('-h', '--help', 'Display this help message') do
        puts config
        exit
      end
    end

    command_line_parser.parse!(args)
    unless args[0]
      puts 'Please specify a database instance.'
      puts
      puts command_line_parser.help
      exit(1)
    end

    unless args[1]
      puts 'Please specify a parameter group.'
      puts
      puts command_line_parser.help
      exit(1)
    end

    command = <<-COMMAND
#{@rds}/rds-modify-db-instance #{args[0]} \
        --db-parameter-group-name #{args[1]} \
        --apply-immediately \
        --show-xml
    COMMAND

    output = `#{command}`
    if $?.to_i != 0
      raise AWSError.new(output)
    end

    puts output
  end


  def aws_database_parameter_group_create(args)
    options = {}
    command_line_parser = OptionParser.new do |config|
      config.banner = 'Usage: aws database parameter group create NAME [options]'

      config.on('--family FAMILY', 'Parameter group family.') do |family|
        options[:family] = family
      end

      config.on('--description DESCRIPTION', 'Description of the parameter group.') do |description|
        options[:description] = description
      end

      config.on('-h', '--help', 'Display this help message') do
        puts config
        exit
      end
    end

    command_line_parser.parse!(args)
    unless args[0]
      puts 'Please specify a parameter group name.'
      puts
      puts command_line_parser.help
      exit(1)
    end

    unless options[:family]
      puts 'Please specify a parameter group family.'
      puts
      puts command_line_parser.help
      exit(1)
    end

    unless options[:description]
      puts 'Please specify a parameter group description.'
      puts
      puts command_line_parser.help
      exit(1)
    end

    command = <<-COMMAND
#{@rds}/rds-create-db-parameter-group #{args[0]} \
        --db-parameter-group-family #{options[:family]} \
        --description='#{options[:description]}' \
        --show-xml
    COMMAND

    output = `#{command}`
    if $?.to_i != 0
      raise AWSError.new(output)
    end

    puts output
  end


  def aws_database_parameter_group_display(args)
    options = {}
    command_line_parser = OptionParser.new do |config|
      config.banner = 'Usage: aws [options] database parameter group display NAME'

      config.on('-h', '--help', 'Display this help message') do
        puts config
        exit
      end
    end

    command_line_parser.parse!(args)
    unless args[0]
      puts 'Please specify a parameter group name.'
      puts
      puts command_line_parser.help
      exit(1)
    end

    command = <<-COMMAND
#{@rds}/rds-describe-db-parameter-groups #{args[0]} --show-xml
    COMMAND

    output = `#{command}`
    if $?.to_i != 0
      raise AWSError.new(output)
    end

    puts output
  end


  def aws_database_parameter_group_modify(args)
    options = {}
    command_line_parser = OptionParser.new do |config|
      config.banner = 'Usage: aws database parameter group modify NAME [options]'

      config.on('--parameter PARAMETER', 'The parameter being modified.') do |parameter|
        options[:parameter] = parameter
      end

      config.on('--value VALUE', 'New value for the parameter.') do |value|
        options[:value] = value
      end

      config.on('-h', '--help', 'Display this help message') do
        puts config
        exit
      end
    end

    command_line_parser.parse!(args)
    unless args[0]
      puts 'Please specify a parameter group name.'
      puts
      puts command_line_parser.help
      exit(1)
    end

    unless options[:parameter]
      puts 'Please specify a parameter name.'
      puts
      puts command_line_parser.help
      exit(1)
    end

    unless options[:value]
      puts 'Please specify a parameter value.'
      puts
      puts command_line_parser.help
      exit(1)
    end

    command = <<-COMMAND
#{@rds}/rds-modify-db-parameter-group #{args[0]} \
        --parameters "name=#{options[:parameter]}, value=#{options[:value]}, method=immediate"
        --show-xml
    COMMAND

    output = `#{command}`
    if $?.to_i != 0
      raise AWSError.new(output)
    end

    puts output
  end
end
