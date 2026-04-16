#!/usr/bin/env dub

import core.exception : SwitchError;

alias CBORException=Exception;

 enum DataType : ubyte{
	UnsignedInteger=0b000,
	NegativeInteger=0b001,
	ByteString=0b010,
	String=0b011,
	List=0b100,//AKA Array
	Map=0b101,
	Tag=0b110,
	Float=0b111//TODO: Consider renaming this to be more generic
}

union DataPrimitive{
	ulong ul;
	double d;
}

struct DataItem{
	DataType _type;
	DataPrimitive _number;
	
	DataItem *_parent;
	ulong[] _tags;

	string _str;//Apparently string cannot exist in the same union, so logic will be checking for what a type is and modifying/reading accordingly.
	ubyte[] _bin_str;
	
	DataItem[] _array;
	//DataItem[DataItem] _dynamic_map;//TODO: Find memory-efficient way to handle having types other than strings...
	//This would be compliant with the CBOR spec, which requires keys able to be part of any of the aforementioned types.

	this(T)(T var){
		static if(is(typeof(T)==int) || is(typeof(T)==long)){
			if(var<0)
				_type=DataType.NegativeInteger;
			else
				_type=DataType.UnsignedInteger;
			_number.ul=var;
		} else static if(is(typeof(T)==uint) || is(typeof(T)==ulong)){
			_type=DataType.UnsignedInteger;
		} else static if(is(typeof(T)==ubyte[])){
			_type=DataType.ByteString;
			_bin_str=var;
		} else static if(is(typeof(T)==string)){
			_type=DataType.String;
			_str=var;
		} else static if(is(typeof(T)==float) || is(typeof(T)==double)){
			_type=DataType.Float;
			_number.d=var;
		}
	}

	this(int i){_type=(i<0) ? DataType.NegativeInteger : DataType.UnsignedInteger;_number.ul=i;}
	this(uint i){_type=DataType.UnsignedInteger;_number.ul=i;}
	this(ulong i){_type=DataType.UnsignedInteger;_number.ul=i;}
	this(double i){_type=DataType.Float;_number.d=i;}
	this(ubyte[] i){_type=DataType.ByteString;_bin_str=i;}
	this(string i){_type=DataType.String;_str=i;}
	this(DataItem[] list){_type=DataType.List; _array=list;}

	this(ulong i, DataType type=DataType.UnsignedInteger){//TODO: Finish types available
		switch(type){
			case DataType.UnsignedInteger:
			case DataType.NegativeInteger:
				//t=DataType.
				//_type=;major
				_number.ul=i;
				break;
			case DataType.Float:
				_number.d=i;
				break;
			default:
				throw new SwitchError("Invalid type");//TODO: Replace with more appropriate error
		}

		_type=type;
	}
	
	@property parent(){return _parent;};//TODO: COnsider removing
	@property parent(DataItem *parent){this._parent=parent;/+debug{import std.stdio; writeln("Parent is now ", *(this._parent), " of type ", _parent._type);}+/};

	T raw(T)(){
		import std.conv : to;
		int scalar=1;
		
		T var;
		static if(is(T==long) || is(T==int)){
			switch(_type){
				case DataType.NegativeInteger:
					scalar=-1;
					goto case;
				case DataType.UnsignedInteger://TODO: This whole section needs to have overflow checking and exceptions added.
					return cast(T)(_number.ul)*scalar;
				case DataType.Float:
					return cast(T)(_number.ul);
				default:
					throw new SwitchError("Not a compatible type");
			}
		} else static if(is(T==ulong) || is(T==uint)){
			switch(_type){
				case DataType.NegativeInteger:
					return cast(T)(_number.ul);
				case DataType.Float:
					return cast(T)_number.d;
				case DataType.UnsignedInteger:
				default:
					return cast(T)(_number.ul);//Assume if they're grabbing an unsigned, they know what they want.
			}
		} else static if(is(T==double)){
			switch(_type){
				case DataType.NegativeInteger:
					scalar=-1;
					goto case;
				case DataType.UnsignedInteger:
					return cast(T)(_number.ul)*scalar;
				case DataType.Float:
					return cast(T)_number.d;
				default:
					return cast(T)(_number.ul)*scalar;
			}
			return cast(T)_number.ul;//Assume if they're grabbing an unsigned, they know what they want.
		} else static if(is(T==ubyte[])){
			return cast(ubyte[])_bin_str;
		} else static if(is(T==string)){
			switch(_type){
				case DataType.NegativeInteger:
					scalar=-1;
					goto case;
				case DataType.UnsignedInteger://TODO: This whole section needs to have overflow checking and exceptions added.
					return (scalar==-1 ? "-" : "")~to!string(_number.ul);
				case DataType.Float:
					return to!string(_number.d);
				case DataType.ByteString:
					return cast(string)(_bin_str);//is this more appropriate than cast(string)?
				case DataType.String:
					return _str;
				case DataType.List:
					import std.array : join;
					return to!string(this._array);
				case DataType.Map:
					string s="{";
					if(!this._array.length)
						return "{}";
					else if(this._array.length%2==1)
						return "{"~cast(string)this._array[0]._str~"}";
					for(int i=0; i<_array.length; i+=2){
						s~=this._array[i].toString()~":"~this._array[i+1].toString();
						if(i!=_array.length-2)
							s~=", ";
					}
					s~="}";
					return s;
				default://TODO:Add map string
					return null;
			}
		}
		//throw new SwitchError("Reached end of funciton");//TODO: Change this to a more appropriate exception.
	}

	string toString(){
		debug{import std.stdio; writeln(this._tags);}
		return this.raw!string();
	}
	
	@property string tostring(){return toString();}

	ulong opUnary(string s)(uint num) if(s=="+"){
			return _number.ul+to!uint(num);
	}
	
	void opOpAssign(string op: "~")(DataItem item){//TODO: Add map support
		this._array~=item;
		this.last().parent=&this;
	}
	
	void opOpAssign(string op: "~")(DataItem key, DataItem value){//TODO: Add error for non-map
		this.array~=item~value;
	}
	
	ref DataItem last(){
		DataItem* d=&(this._array[$-1]);
		return *d;
	}
	
	bool mapify(){
		if((this._array.length%2)!=0)
			throw new Exception("Needs to be divisible by two. Got "~this.toString());
		return true;
	}
	
	bool isNumber() const @trusted{
		import std.algorithm : canFind;
		return ([DataType.UnsignedInteger, DataType.NegativeInteger, DataType.Float].canFind(this._type));
	}
	
	bool opEquals(ref const DataItem item) const @trusted{
		return false;//TODO Right away 
	}
	
	bool opEquals(long item) const @trusted{
		int sign=1;
		if(!this.isNumber)
			return false;
		else if(this._type==DataType.NegativeInteger)
			sign=-1;
		else if(this._type==DataType.Float)
			return item==this._number.d;
		return false;
	}
	
	bool opEquals(ulong n) const @trusted{
		if(this._type==DataType.UnsignedInteger)
			return this._number.ul==n;
		else if(this._type==DataType.Float)
			return cast(ulong)this._number.d==n;
		return false;
	}
	
	bool opEquals(int n) @trusted{
		return this.opEquals(cast(long)(n));
	}
	
	bool opEquals(double n){
		if(this._type==DataType.UnsignedInteger)
			return this._number.ul==n;
		else if(this._type==DataType.NegativeInteger)
			return cast(double)(this._number.ul*-1)==n;
		else if(this._type==DataType.Float)
			return this._number.d==n;
		return false;
	}
	
	bool opEquals(string s){//TODO: Add binary string, list and map comparison
		if(!this._type==DataType.String)
			return false;
		return this._str==s;
	}
	
	DataItem* opIndex(ulong i){
		if(this._type==DataType.List)
			return &this._array[i];//TODO: Consider convenience function for maps with ulong, also add string indexing
		return  new DataItem("NULL");//Implement proper null
	}
	
	DataItem* opIndex(DataItem item){
		if(this._type==DataType.List)
			return /+new DataItem(+/this[item.raw!ulong];
		else if(this._type!=DataType.Map)
			throw new Exception("Not array or list");//TODO: Implement string indexing by char
		for(int i=0; i<this._array.length; i+=2)
			if(this._array[i]==item){//debug{import std.stdio;writeln("L t");}//May have to just call raw
				return &this._array[i+1];}
		return new DataItem("NULL ITEM");//Implement proper null
	}
	
	@property ulong length(){
		if(this._type==DataType.List) return this._array.length;
		else if(this._type==DataType.Map) return this._array.length/2;
		return 1;
	}
	
	@property void tags(ulong[] tags){
		this._tags=tags;
	}
	
	@property ulong[] tags(){
		return this._tags;
	}
	
	void addTag(ulong tag){
		this._tags~=tag;
	}
}

ulong getUnsignedFromCBOR(ubyte[] inputArray, ulong startingPoint=0){
	/++
	This function gets the unsigned value of a CBOR integer, it has no concern for sign!
	Additionally, it does not care for single length items, it will just return the same item.
	
	Internal use
	++/
	ulong argument=0;

	if(inputArray.length==1)
		return inputArray[0] & 31;//TODO: Throw an error if this is over 23
	
	for(int i=cast(int)startingPoint+1; i<inputArray.length; i++){
		argument=(argument << 8) + inputArray[i];}

	return argument;
}

ubyte[] _getCBORArgument(ref ubyte[] sourceArray, ulong startingPoint=0, bool includeAdditional=false){
	/++INTERNAL USE-FUNCTION
	Every function called by this needs to be rewritten probably. It now includes the additionalInformation from item 1, Initially, it did not.
	+/
	ubyte additionalInformation=sourceArray[startingPoint] & 31,//TODO: Must implement infinite length items i.e. argument 31
			argumentSize=1;
	
	if(24<=additionalInformation && additionalInformation<=27)
		argumentSize <<= (additionalInformation - 24);//If argumentSize>23, the rest is relevant, if it's that or under, it's actually the entire argument.
	else
		return [(additionalInformation)];
		
	startingPoint++;
	
	return (includeAdditional ? [additionalInformation] : []) ~ sourceArray[startingPoint .. startingPoint+argumentSize];
}

DataItem getCBORByteString(ref ubyte[] sourceArray, ulong startingPoint=0){
	/++
	Get CBOR Byte String.
	Warning: This function does not yet support infinite length items
	+/
	ubyte[] array=_getCBORArgument(sourceArray, startingPoint, true);
	ulong stringLength=getUnsignedFromCBOR(array, 0);
	startingPoint+=array.length-1;
	
	return DataItem(sourceArray[++startingPoint .. startingPoint+stringLength]);
}

DataItem getCBORString(ref ubyte[] sourceArray, ulong startingPoint=0){
	return DataItem(cast(string)(getCBORByteString(sourceArray, startingPoint)._bin_str));//TODO: MAke this more efficient by use an intermediary function for these two.
}

DataItem fromCBOR(ubyte[] sourceArray, bool strict=false);

ulong _getCBORListByteLength(ref ubyte[] sourceArray, ulong startingPoint){
	ulong elementCount=sourceArray[startingPoint] & 31;
	return 0;//TODO: Implement or delete
}

bool insertToLastItem(ref DataItem[] array, DataItem item, ulong depth/+=1+/, bool makeMap){
	//TODO: Make this more memory safe
	ulong d=0;
	depth--;
	DataItem* currentElement=&array[$-1];
	DataItem* modified=&item;
	while((*currentElement)._array.length && 
		((*currentElement)._type==DataType.List || (*currentElement)._type==DataType.Map)/+ &&
				(*currentElement).last()._type==DataType.List+/ && ++d<depth){
		(currentElement)=(&currentElement.last());
	}
	
	(*currentElement)~=item;
	return true;
}

DataItem getCBORList(ref ubyte[] sourceArray, ulong startingPoint=0){
	import std.range : popBack;
	DataItem[] items;
	ubyte[] argument=_getCBORArgument(sourceArray, startingPoint, true);
	ulong itemIndex=0, itemDepth=0, index=startingPoint, length=getUnsignedFromCBOR(argument);
	ulong[] tags;//Technically ulong is the highest a tag can be, but consider switching back to uint.
	
	if(sourceArray[startingPoint] >> 5==5)
		length*=2;
	ulong[] depthList=[length];
	
	index++;
	debug{import std.stdio;}
	
	while(itemIndex<length){
		ubyte itemType=sourceArray[index] >> 5;
		argument=_getCBORArgument(sourceArray, index, true);
		ulong argumentValue=getUnsignedFromCBOR(argument);
		DataItem item;
		DataItem[] listItem;
		
		final switch(itemType){
			case 0:
			case 1:
				item=DataItem(argumentValue+itemType);
				if(itemType)
					item._type=DataType.NegativeInteger;
				item.tags=tags;
				tags.length=0;
				if(depthList.length>1)
					insertToLastItem(items, item, depthList.length, false);
				else
					items~=item;
				index+=argument.length;
				break;//TODO: REmove
			case 2://TODO
			case 3:
				item=getCBORString(sourceArray, index);
				item.tags=tags;
				tags.length=0;
				if(depthList.length>1)
					insertToLastItem(items, item, depthList.length, false);//TODO: figure out depth
				else
					items~=item;
				index+=argument.length+argumentValue;
				break;
			case 5://TODO
				argumentValue*=2;
				item=DataItem(listItem);
				item._type=DataType.Map;
				length+=argumentValue;
				index+=argument.length;
				
				item.tags=tags;
				tags.length=0;
				
				if(depthList.length>1)
					insertToLastItem(items, item, depthList.length, true);
				else
					items~=(item);
					
				if(depthList.length>1)//This must be before appending, to offset the previous depth
					depthList[$-1]--;
				depthList~=argumentValue+1;//length would make most sense, total count is easier to keep track of though
				break;
				
			case 4://TODO
				item=DataItem(listItem);
				item._type=DataType.List;
				length+=argumentValue;
				index+=argument.length;
				
				item.tags=tags;
				tags.length=0;
				
				if(depthList.length>1) 
					insertToLastItem(items, item, depthList.length, false);
				else
					items~=(item);
					
				if(depthList.length>1)//This must be before appending, to offset the previous depth
					depthList[$-1]--;
				depthList~=argumentValue+1;//length would make most sense, total count is easier to keep track of though
				break;
			case 6:
				tags~=argumentValue;
				length+=argumentValue;
				depthList[$-1]++;
				index+=argument.length;
				break;
			case 7:
			//default:
			//	break;
		}
		
		itemIndex++;
		if(depthList.length && depthList[$-1]>0)
			depthList[$-1]--;
		while(depthList.length && depthList[$-1]==0)
			depthList.popBack();//:)
		debug{writeln("Depth: ", depthList);}
		debug{writeln(itemIndex, "/", length, ": ", index);}
		debug{writeln(items);}
	}
	return DataItem(items);
}

DataItem fromCBOR(ubyte[] sourceArray, bool strict=false){//Refactor: Clean this up, get rid of recursion.
	import std.math : pow;
	import std.conv : ConvException, to;
	DataType t;
	DataItem[] list;

	ulong position=0;
	ubyte major=sourceArray[position] >> 5;//Major type is first 3 bits of the first argument
	ulong[] tags;
	
	ubyte[] argument=_getCBORArgument(sourceArray, position);
	
	while(major==6){
		major=sourceArray[position] >> 5;
		argument=_getCBORArgument(sourceArray, position);
		tags~=getUnsignedFromCBOR(argument);
		position+=argument.length;
	}
	
	switch(major){
		case 0:
		case 1:
			return DataItem(getUnsignedFromCBOR(sourceArray, position)+major, major ? DataType.NegativeInteger : DataType.UnsignedInteger);
		case 2:
			return getCBORByteString(sourceArray, position);
		case 3:
			return getCBORString(sourceArray, position);//DataItem();//TODO
		case 4:
			return getCBORList(sourceArray, position);
		case 5:
			DataItem item=getCBORList(sourceArray, position);
			item._type=DataType.Map;
			return item;
		case 7:
			//TODO:Implement
		default:
			return DataItem(0);//TODO: Change ASAP
	}
}


unittest{
	import std.stdio : writeln;
	import std.exception : assertThrown, assertNotThrown;

	// Helper to reduce repetition
	void testDecode(string description, ubyte[] data, string expectedStr,
					bool strict = false, bool shouldThrow = false)
	{
		if (shouldThrow) {
			assertThrown!CBORException(fromCBOR(data, strict), description);
			return;
		}

		DataItem item = fromCBOR(data, strict);
		writeln(item);
		assert(item.toString() == expectedStr,
			   description ~ " failed. Got: " ~ item.toString() ~ " Expected: " ~ expectedStr);
	}

	// === Positive Integers (Type 0) ===
	testDecode("uint 0",		  [0x00], "0");
	testDecode("uint 10",		 [0x0A], "10");
	testDecode("uint 100",		[0x18, 0x64], "100");
	testDecode("uint 1000",	   [0x19, 0x03, 0xE8], "1000");

	// === Negative Integers (Type 1) ===
	testDecode("nint -1",	 	[0x20], "-1");   // Note: your raw!string may need tweaking for negative display
	testDecode("nint -10",		[0x29], "-10");
	testDecode("nint -100",		[0x38, 0x63], "-100");

	// === Byte Strings (Type 2) - plain integer bytes ===
	testDecode("byte empty",		[0x40], "");					// toString may return empty
	testDecode("byte h'2A'",		[0x41, 0x2A], "[42]");		 // adjust if your toString for bytes is different
	testDecode("byte h'010203'",	[0x43, 0x01, 0x02, 0x03], "[1, 2, 3]");

	// === Text Strings (Type 3) ===
	testDecode("text empty",	[0x60], "");
	testDecode("text 'a'",		[0x61, 0x61], "a");
	testDecode("text 'hello'",	[0x65, 0x68, 0x65, 0x6C, 0x6C, 0x6F], "hello");

	// === Arrays (Type 4) with nesting ===
	testDecode("array empty",	 [0x80], "[]");				  // depends on your List toString
	testDecode("array [1,2,3]",  [0x83, 0x01, 0x02, 0x03], "[1, 2, 3]");
	testDecode("array [-1,-2]",  [0x82, 0x20, 0x21], "[-1, -2]");

	// Mixed + nested
	testDecode("mixed array", [
		0x84,
		0x18, 0x64,					// 100
		0x39, 0x03, 0xE7,			// -1000
		0x42, 0xCA, 0xFE,			// byte string CA FE
		0x65, 0x74, 0x65, 0x73, 0x74, 0x21   // "test!"
	], "[100, -1000, [202, 254], test!]");   // adjust expected string to match your toString output

	testDecode("nested arrays", [
		0x82,
		0x82, 0x01, 0x02,			  // [1, 2]
		0x83, 0x03, 0x04, 0x05		 // [3, 4, 5]
	], "[[1, 2], [3, 4, 5]]");

	// === Strict mode error cases ===
	testDecode("overlong uint 0 (strict)", [0x18, 0x00], "", true, true);   // should throw
	testDecode("truncated array (strict)", [0x82, 0x01], "", true, true);
	testDecode("invalid additional info (strict)", [0x1F], "", true, true);

	// Non-strict should not throw on these (or handle gracefully)
	assertNotThrown(fromCBOR([0x18, 0x00], false));   // overlong 0

	writeln("All CBOR unit tests passed!");
}