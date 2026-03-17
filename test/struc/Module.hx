package struc;

class Module {
    static var counter:Int = 0;
    public var id:Int;
    public var name:String;

    static var struct:StructIInit = new StructIInit();
}
@:structInit
class StructIInit {
    public var a:Int = 42;
    public var b:String = "hello";
    public var c:Float = 3.14;
    public var d:Bool = true;

    public function new() {}
}