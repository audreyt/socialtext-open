proto = new Subclass('Test.YAML', 'Test.Base');

proto.init = function() {
    Test.Base.prototype.init.call(this);
    this.block_class = 'Test.YAML.Block';
    this.section_delim = '+++';
}

proto = Subclass('Test.YAML.Block', 'Test.Base.Block');

proto.init = function() {
    Test.Base.Block.prototype.init.call(this);
    this.filter_object = new Test.YAML.Filter();
}

proto = new Subclass('Test.YAML.Filter', 'Test.Base.Filter');

proto.eval_dump_js = function(content, block) {
    try {
        var node = eval(content);
    }
    catch(e) {
        throw("Error attempting to eval '" + content + "'");
    }
    return YAML.dump(node);
}

