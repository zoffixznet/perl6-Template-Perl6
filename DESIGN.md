# Design of Template::Perl6

## Purpose

The module must provide a templating language that has virtually no
learning quote and is easily utilizable for a wide variety of types of
documents. The templates must be usable in a high-performance environments.

## Requirements

The language must:

* Be extremely easy to learn
* Allow to freely change any of the delimiters used
* Provide very simple means to pass data into the template
* Provide looping and logic constructs
* Make it possible to load + render + output a template in as few steps
    as possible

In addition:

* Looping and variable constructs must not, unintentionally, add any additional
whitespace into the template. That is, they must be replaced by their output
exactly, regardless of the position of the delimiters.

### Constraints

It is expected the templates will be used in high-performance environments,
such as web applications. As such, speed is an important quality. While RAM
is secondary, it is not limitless either.

The initial requirements assume a template of 100KB in side and moderate
amount of logic and variables. It must be possible render it **at least 1000
times per second** while using at most **300MB of RAM.** An initial parsing and
caching stage is permitted, but **must not exceed** the RAM limitation and must
not take more than **1 second**.

## Architecture
