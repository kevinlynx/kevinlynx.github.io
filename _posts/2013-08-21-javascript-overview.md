---
layout: post
title: "Javascript Overview"
categories: Javascript
tags: [javascript]
comments: true
keywords: [javascript]
description: 
---

## Lexical Structure

In JavaScript, identifiers are used to name variables and functions and to provide labels for certain loops in JavaScript code. A JavaScript identifier must begin with a letter, an underscore (_), or a dollar sign ($). Subsequent characters can be letters, digits, underscores, or dollar signs

	i
	abc
	v1
	$str

JavaScript allows identifiers to contain letters and digits from the entire Unicode character set.

Like many programming languages, JavaScript uses the semicolon (;) to separate statements from each other. In JavaScript, you can usually omit the semicolon between two statements if those statements are written on separate lines.

## Types/Values/Variables

### Numbers

Unlike many languages, JavaScript does not make a distinction between integer values and floating-point values. All numbers in JavaScript are represented as floating-point values.

	0
	3
	0xff
	3.14

### Strings

	"hello world"
	'hello world'
	"Wouldn't you prefer O'Reilly's book?"	
<!-- more -->
### Boolean

	true
	false

Any JavaScript value can be converted to a boolean value. The following values convert to, and therefore work like, `false`:

	undefined
	null
	0
	-0
	NaN
	"" // the empty string

### null/undefined

`null` is a language keyword that evaluates to a special value that is usually used to indicate the absence of a value. Using the typeof operator on null returns the string "object", indicating that null can be thought of as a special object value that indicates "no object".

### Objects

JavaScript objects are composite values: they are a collection of properties or named values.

	var s = "hello world!"; // A string
	var word = s.substring(s.indexOf(" ")+1, s.length);
 	var obj = {
        propName1: 123,
        propName2: "abc"
    };
    obj.propName1 = 456;
    obj["propName1"] = 456; // same as previous statement

### Arrays

Arrays are a specialized kind of object. JavaScript arrays are untyped: an array element may be of any type, and different elements of the same array may be of different types.

	var empty = []; // An array with no elements
	var primes = [2, 3, 5, 7, 11]; // An array with 5 numeric elements
	var misc = [ 1.1, true, "a", ]; // 3 elements of various types + trailing comma

Another way to create an array is with the Array() constructor:

	var a = new Array();
	var a = new Array(10);
	var a = new Array(5, 4, 3, 2, 1, "testing, testing");

### Functions

Functions designed to initialize a newly created object are called **constructors**. In JavaScript, **functions are objects**. JavaScript can assign functions to variables and pass them to other functions. JavaScript function definitions can be nested within other functions.

	function printprops(o) {
		for(var p in o)
		console.log(p + ": " + o[p] + "\n");
	}
	var square = function(x) { return x*x; }

	function hypotenuse(a, b) {
		function square(x) { return x*x; }
		return Math.sqrt(square(a) + square(b));
	}

## Expressions/Operators

### Object and Array initializers

	var p = { x:2.3, y:-1.2 }; // An object with 2 properties
	var q = {}; // An empty object with no properties
	q.x = 2.3; q.y = -1.2; // Now q has the same properties as p
	var matrix = [[1,2,3], [4,5,6], [7,8,9]];

### Object creation expression

An object creation expression creates a new object and invokes a function (called a constructor) to initialize the properties of that object.

	new Object()
	new Point(2,3)

### Operators

* Arithmetic operator
* Relational operator
* Logical operator
* Assignment operator
* Conditional operator
* `typeof` operator
* `delete` operator

### `eval` expression

JavaScript has the ability to interpret strings of JavaScript source code, evaluating them to produce a value. JavaScript does this with the global function `eval()`:

	eval("3+2") // => 5

## Statements

### Declaration Statements

The var statement declares a variable or variables. Here’s the syntax:

	var name_1 [ = value_1] [ ,..., name_n [= value_n]]	

### Conditionals

	if (expression)
		statement	
	else if (expression)
		statement

	switch(expression) {
		statements
	}

### Loops

	while (expression)
		statement

	do
		statement
	while (expression);

	for(initialize ; test ; increment)
		statement

	for (variable in object)
		statement

	var o = {a:1, b:2};
	for(var p in o) // Assign property names of o to variable p
		console.log(o[p]); // Print the value of each property

### Other

* break/break label
* continue/continue label
* return
* throw
* try/catch/finally
* with
* use strict

## Objects

An object is more than a simple stringtovalue map, however. In addition to maintaining its own set of properties, a JavaScript object also inherits the properties of another object, known as its "prototype". The methods of an object are typically inherited properties, and this "prototypal inheritance" is a key feature of JavaScript.

JavaScript objects are dynamic—properties can usually be added and deleted—but they can be used to simulate the static objects and “structs” of statically typed languages.

**Objects are mutable and are manipulated by reference rather than by value.**

Every JavaScript object has a second JavaScript object (or null, but this is rare) associated with it. This second object is known as a **prototype**.

Objects created using the new keyword and a constructor invocation use the value of the prototype property of the constructor function as their prototype.

`Object.create()` creates a new object, using its first argument as the prototype of that object.

	var o1 = Object.create({x:1, y:2}); // o1 inherits properties x and y.

If you want to create an ordinary empty object (like the object returned by {} or new Object()), pass Object.prototype:

	var o3 = Object.create(Object.prototype); // o3 is like {} or new Object().

The `delete` operator removes a property from an object:

	delete book.author; // The book object now has no author property.
	delete book["main title"]; // Now it doesn't have "main title", either.

### property getters and setters

Properties defined by getters and setters are sometimes known as accessor properties to distinguish them from data properties that have a simple value.

	var p = {
		// x and y are regular read-write data properties.
		x: 1.0,
		y: 1.0,
		// r is a read-write accessor property with getter and setter.
		// Don't forget to put a comma after accessor methods.
		get r() { return Math.sqrt(this.x*this.x + this.y*this.y); },
		set r(newvalue) {
			var oldvalue = Math.sqrt(this.x*this.x + this.y*this.y);
			var ratio = newvalue/oldvalue;
			this.x *= ratio;
			this.y *= ratio;
		},
		// theta is a read-only accessor property with getter only.
		get theta() { return Math.atan2(this.y, this.x); }
	};

## Functions

In JavaScript, functions may be nested within other functions. For example:

	function hypotenuse(a, b) {
		function square(x) { return x*x; }
		return Math.sqrt(square(a) + square(b));
	}	

### Invoking functions

JavaScript functions can be invoked in four ways:

* as functions
* as methods
* as constructors
* indirectly through their call() and apply() methods

### Optional parameters

	// Append the names of the enumerable properties of object o to the
	// array a, and return a. If a is omitted, create and return a new array.
	function getPropertyNames(o, /* optional */ a) {
		if (a === undefined) a = []; // If undefined, use a new array
		for(var property in o) a.push(property);
		return a;
	}
	// This function can be invoked with 1 or 2 arguments:
	var a = getPropertyNames(o); // Get o's properties into a new array
	getPropertyNames(p,a); // append p's properties to that array

### Variable-Length Argument Lists: The Arguments Object

	function max(/* ... */) {
		var max = Number.NEGATIVE_INFINITY;
		// Loop through the arguments, looking for, and remembering, the biggest.
		for(var i = 0; i < arguments.length; i++)
		if (arguments[i] > max) max = arguments[i];
		// Return the biggest
		return max;
	}
	var largest = max(1, 10, 100, 2, 3, 1000, 4, 5, 10000, 6); // => 10000

In addition to its array elements, the Arguments object defines callee and caller properties.

	var factorial = function(x) {
		if (x <= 1) return 1;
		return x * arguments.callee(x-1);
	};

### Function as values

Functions are not primitive values in JavaScript, but a specialized kind of object, which means that functions can have properties.

	// Initialize the counter property of the function object.
	// Function declarations are hoisted so we really can
	// do this assignment before the function declaration.
	uniqueInteger.counter = 0;
	// This function returns a different integer each time it is called.
	// It uses a property of itself to remember the next value to be returned.
	function uniqueInteger() {
		return uniqueInteger.counter++; // Increment and return counter property
	}

### Closures

Like most modern programming languages, JavaScript uses lexical scoping.

### Function bind method

When you invoke the bind() method on a function f and pass an object o, the method returns a new function. Invoking the new function (as a function) invokes the original function f as a method of o. Any arguments you pass to the new function are passed to the original function.

	function f(y) { return this.x + y; } // This function needs to be bound
	var o = { x : 1 }; // An object we'll bind to
	var g = f.bind(o); // Calling g(x) invokes o.f(x)
	g(2) // => 3	

### The Function() Constructor

Functions are usually defined using the function keyword, either in the form of a function definition statement or a function literal expression. But functions can also be defined with the Function() constructor. For example:

	var f = new Function("x", "y", "return x*y;");

## Reference

* \<Javascript The Definitive Guid 6th\>
* [A Survey of the JavaScript Programming Language](http://javascript.crockford.com/survey.html)
* [A quick overview of JavaScript](http://www.2ality.com/2011/10/javascript-overview.html)
* [JavaScript Summary](http://www.csse.monash.edu.au/~lloyd/tildeProgLang/JavaScript/summary.html)


