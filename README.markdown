Doozque
======

Doozque is a fork of Resque which replaces Redis for
[Doozer](https://github.com/ha/doozer). It is an hacky experiment.

Why?
---

Resque is awesome and so is Redis. But Redis is not distributed\*. If your
redis server goes down, then so does your ability to process jobs.
Doozer is a distributed and can be setup in a fault tolerent way. You
can loose doozerd instances and still process background jobs.

Demo
----

First start doozerd on `127.0.0.1:8046`. Add some more doozerd's if you
like. \*NOTE\* you must run this fork of fraggle-block
[fraggle-block](http://github.com/benburkert/fraggle-block).

    % cd examples/demo
    % bundle
    % bundle exec rackup &
    % bundle exec rake doozque:worker QUEUE=*

Browse to `http://127.0.0.1:9292` and run some jobs. Also check out
`http://127.0.0.1:8000` to check out what's happening in your doozer db.
