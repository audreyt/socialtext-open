var t = new Test.Performance();

t.plan(3);

t.timedLoad(".", 200, "Network latency check");
t.timedLoad(".", 200, "Network latency check");
t.timedLoad(".", 200, "Network latency check");
