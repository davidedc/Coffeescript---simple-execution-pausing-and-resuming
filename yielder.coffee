###
A program that takes a Coffeescript function in input (as string), and transforms it into a new Coffeescript function (as string) that can be executed step by step, by using Generators.

The idea is to transform the original function into a Generator and adding "yield" after each line in it. In this way the function can be run step by step by doing:

for n from the_function_tranformed_to_generator()
  console.log "running a step"

So this is how the function should be transformed:
* every line should be followed by a line with the string "yield", making sure it's indented correctly
* if there is a function call it should be transformed like this:
myCont = aFunctionCall(arguments); yield while (!(myCont.next()).done)


LIMITATIONS:
So it looks like making a program step-executable" by transforming functions into generators (which you can step through using next()) has flaw: it's not really easy to transform functions into yielding functions (i.e. generators) in general, in some cases it gets complicated.
Example: foo calling bar calling baz. So, baz and bar both return continuations, and foo is the top level and is the one that needs to do the next(). But wait, "bar" wants a result from "baz", so it needs to do "next()" too to get the final result.
In some cases it's easy i.e.:
  baz arg1, arg2
can be easily transformed into
  yield from baz arg1, arg2, arg3
However if bar calls baz in an assignment like so:
  assignee = baz(arg1, arg2) + 1
how the hell do you handle that? Cause "baz()" returns a continuation, so you can't add that to a number.
You could do it by replacing baz() with something of this flavour (myCont = baz(arg1, arg2); while result = myCont().next() yield else return result)
...but there is no easy way to capture and manipulate function calls with regexes.
Thigs get even more complicated in case of nested calls etc., you see where the problem is.

So what we are doing here is
* we tackle only simple cases
* we assume that all functions that are actually generators are known in advance

TODO
* Automatically detect (from comments first) which functions should become generators and which should not.
   if it has a yield, it's a generator
   if it calls a generator, it's a generator
   ...handle that by actually renaming the funcX to funcXGenerator so you have a clear picture and you can
  also easily...
* Provide warning when you call a generator from a non-generator function
* Better regexps for variables and function names
* Handling of
   console.log funct_generator args
* Warning when you make a complex invocation of a generator i.e. anything other than
   a) assignee = invocation
   b) console.log invocation
* add the pause thing i.e. pause/wait are just a yield with a "resume conditional" defined before it
###

indentLevel = 0

transformFunctionToGenerator = (functionStr) ->
  # Remove leading/trailing spaces and split into lines
  lines = (functionStr.trim()).split('\n')

  # helper function to add the "yield" keyword in its own line
  # at a given indentation level 
  addYield = (line, indentLevel) ->
    indent = '  '.repeat indentLevel
    return "#{line}\n#{indent}yield"

  # helper function to transform function calls without assignments
  transformFunctionCallWithoutAssignment = (match, line, indentLevel) ->
    indent = '  '.repeat indentLevel
    functionName = match[1]
    thearguments = match[2]
    # "yield from X" causes _this_ generator to yield all the values from the called generator X
    return "#{indent}yield from #{functionName} #{thearguments}"

  transformFunctionCallWithAssignment = (match, line, indentLevel) ->
    indent = '  '.repeat indentLevel
    assignee = match[1]
    functionName = match[2]
    thearguments = match[3]
    # this is quite a rigamarole to be able to BOTH yield the intermediate steps AND return the final result so it can be assigned to a variable...
    # turns out that after you yield following a "done", you go "past" (i.e. "beyond") the last value, so you need to store the previous value in a shifting array
    # (I mean you could do it with two variables instead of an array)
    return "#{indent}myCont = #{functionName}(#{thearguments}); nextVal = ['','']; yield while (!([next = myCont.next(),nextVal[1]=nextVal[0], nextVal[0]=next.value][0]).done); #{assignee} = nextVal[1]"

  # Iterate over each line of the function and transform it
  transformedLines = []
  for line in lines
    trimmedLine = line.trim()
    
    # count how many double spaces there are at the beginning of the line
    # and figure out the indentation level from that
    numberOfSpaces = line.match(/^ */)[0].length
    indentLevel = numberOfSpaces / 2
    
    # stuff that indents what's below e.g. function defs, loops
    # TODO if statements, while, for, 
    if line.includes('->') or line.includes('loop')
      transformedLines.push addYield line, indentLevel + 1
    
    # no need to add a yield after comments or returns
    else if (trimmedLine.startsWith '#') or (trimmedLine.startsWith 'return')
      transformedLines.push line
    
    # Handle function calls with an assignment
    else if (!line.includes('console.log')) and line.includes('_generator') and (match = line.match(/ *(\w+) *= *(\w+)([ \(]+.*)/))
      transformedLines.push transformFunctionCallWithAssignment(match, line, indentLevel)
    
    # Handle function calls without an assignment
    else if (!line.includes('console.log')) and line.includes('_generator') and (match = line.match(/ *(\w+)([ \(]+.*)/))
      transformedLines.push transformFunctionCallWithoutAssignment(match, line, indentLevel)
    
    # everything else
    else
      transformedLines.push addYield(line, indentLevel)

    
  # Combine the transformed lines into a single string
  return transformedLines.join '\n'



# Define the original functions as strings
printResultStr = """
printResult = (a) ->
  console.log "> \#{a}"
  return
"""

assignableGener = """
func2_generator = (a) ->
  yield "one"
  yield "two"
  yield "three"
  return
"""


writeResultStr = """
func_generator = (a) ->
  # note that printResult is not a generator so this call is not transformed
  printResult a
  return
"""

perfectSquaresStr = """
perfectSquares = ->
  num = 0
  assigned = func2_generator 9
  console.log assigned
  loop
    num++
    stepResult = num*num
    func_generator stepResult
  console.log "we'll never get here"
  return
"""

# Transform the functions into generators
writeResultGeneratorStr = transformFunctionToGenerator(writeResultStr)
perfectSquaresGeneratorStr = transformFunctionToGenerator(perfectSquaresStr)

console.log ""
console.log printResultStr

console.log ""
console.log assignableGener

console.log ""
console.log writeResultGeneratorStr

console.log ""
console.log perfectSquaresGeneratorStr

console.log ""
console.log """
console.log "-------------------------------------------------"
theGenerator = perfectSquares()
for i in [1..25]
  theGenerator.next()
  console.log "-- stopped at yield no. \#{i}:"
"""
