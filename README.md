Tool
====

Installation
------------

Copy the source to a local directory and add 'bin' to PATH.

In order to use AWS related commands, you will need to create a directory ${HOME}/.tool and
add your AWS private key and cert files to it. If such a directory by some other name already exists,
you could also set an environment variable TOOL_AWS_CONFIG to point to it.

Usage
-----

This command line intends to be self documenting. To begin, simply type "tool".

Example:

    $ tool
    Usage:
	    tool aws ...

    $ tool aws
    Usage:
      tool aws database ...
	    tool aws instance ...
	    tool aws role ...
