# IRB

IRB stands for "interactive Ruby" and is a tool to interactively execute Ruby expressions read from the standard input.

The `irb` command from your shell will start the interpreter.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'irb'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install irb

## Usage

Use of irb is easy if you know Ruby.

When executing irb, prompts are displayed as follows. Then, enter the Ruby expression. An input is executed when it is syntactically complete.

```
$ irb
irb(main):001:0> 1+2
#=> 3
irb(main):002:0> class Foo
irb(main):003:1>   def foo
irb(main):004:2>     print 1
irb(main):005:2>   end
irb(main):006:1> end
#=> nil
```

The Readline extension module can be used with irb. Use of Readline is default if it's installed.

## Commands

The following commands are available on IRB. You can get the same output from the `show_cmds` command.


```
IRB
  cwws           Show the current workspace.
  chws           Change the current workspace to an object.
  workspaces     Show workspaces.
  pushws         Push an object to the workspace stack.
  popws          Pop a workspace from the workspace stack.
  irb_load       Load a Ruby file.
  irb_require    Require a Ruby file.
  source         Loads a given file in the current session.
  irb            Start a child IRB.
  jobs           List of current sessions.
  fg             Switches to the session of the given number.
  kill           Kills the session with the given number.
  irb_info       Show information about IRB.
  show_cmds      List all available commands and their description.

Debugging
  debug          Start the debugger of debug.gem.
  break          Start the debugger of debug.gem and run its `break` command.
  catch          Start the debugger of debug.gem and run its `catch` command.
  next           Start the debugger of debug.gem and run its `next` command.
  delete         Start the debugger of debug.gem and run its `delete` command.
  step           Start the debugger of debug.gem and run its `step` command.
  continue       Start the debugger of debug.gem and run its `continue` command.
  finish         Start the debugger of debug.gem and run its `finish` command.
  backtrace      Start the debugger of debug.gem and run its `backtrace` command.
  info           Start the debugger of debug.gem and run its `info` command.

Misc
  edit           Open a file with the editor command defined with `ENV["EDITOR"]`.
  measure        `measure` enables the mode to measure processing time. `measure :off` disables it.

Context
  show_doc       Enter the mode to look up RI documents.
  ls             Show methods, constants, and variables. `-g [query]` or `-G [query]` allows you to filter out the output.
  show_source    Show the source code of a given method or constant.
  whereami       Show the source code around binding.irb again.
```

## Configuration

### Environment Variables

- `NO_COLOR`: Assigning a value to it disables IRB's colorization.
- `IRB_USE_AUTOCOMPLETE`: Setting it to `false` disables IRB's autocompletion.
- `EDITOR`: Its value would be used to open files by the `edit` command.
- `IRBRC`: The file specified would be evaluated as IRB's rc-file.

## Documentation

https://docs.ruby-lang.org/en/master/IRB.html

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby/irb.

## Releasing

```
rake release
gh release create vX.Y.Z --generate-notes
```

## License

The gem is available as open source under the terms of the [2-Clause BSD License](https://opensource.org/licenses/BSD-2-Clause).
