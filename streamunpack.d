//Exception
import core.exception : SwitchError;

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

	string _str;//Apparently string cannot exist in the same union, so logic will be checking for what a type is and modifying/reading accordingly.
	ubyte[] _bin_str;
	DataItem[] _array;
	DataItem[string] _dynamic_map;//TODO: Find memory-efficient way to handle having types other than strings...
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
	this(DataItem[] list){_type=DataType.List; _array=list;
			debug{import std.stdio : writeln; writeln("val is ", _array);}}

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
					/*debug{writeln("unsiGNED INTEGER");}*/return cast(T)(_number.ul)*scalar;
				case DataType.Float:
					return cast(T)(_number.ul);
				default:
					throw new SwitchError("Not a compatible type");
			}
		} else static if(is(T==ulong) || is(T==uint)){
			switch(_type){
				case DataType.NegativeInteger:
				case DataType.UnsignedInteger:
					return cast(T)(_number.ul);
				case DataType.Float:
					return cast(T)_number.d;
				default:
					return cast(T)(_number.ul);
			}
			return cast(T)_number.ul;//Assume if they're grabbing an unsigned, they know what they want.
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
					import std.string : assumeUTF;
					return assumeUTF(_bin_str);//is this more appropriate than cast(string)?
				case DataType.String:
					return _str;
				case DataType.List:
					import std.array : join;
					return to!string(this._array);
				default://TODO:Add map string
					return null;
			}
		}
		return cast(T)var;
		//throw new SwitchError("Reached end of funciton");//TODO: Change this to a more appropriate exception.
	}

	string toString(){
		return this.raw!string();
	}

	ulong opUnary(string s)(uint num) if(s=="+"){
			return _number.ul+to!uint(num);
	}
	
	void opOpAssign(string op: "~")(DataItem item){//TODO: Add map support
		import std.stdio : writeln;
		
		writeln("WOAAAAH", op);
	}
	
	DataItem last(){
		return this._array[$-1];
	}
}

ulong getUnsignedFromCBOR(ubyte[] inputArray, int startingPoint=0){
	/++
	This function gets the unsigned value of a CBOR integer, it has no concern for sign!
	Additionally, it does not care for single length items, it will just return the same item.
	
	Internal use
	++/
	ulong argument=0;

	if(inputArray.length==1)
		return inputArray[0] & 31;//TODO: Throw an error if this is over 23
	
	for(int i=cast(int)startingPoint+1; i<inputArray.length; i++){
		argument=(argument << 8) + inputArray[i];
		}

	return argument;
}

ubyte[] _getCBORArgument(ref ubyte[] sourceArray, ulong startingPoint=0, bool includeAdditional=false){
	/++INTERNAL USE-FUNCTION
	Every function called by this needs to be rewritten probably. It now includes the additionalInformation from item 1, Initially, it did not.
	+/
	ubyte additionalInformation=sourceArray[startingPoint] & 31,
			argumentSize=1;
	//TODO: Must implement infinite length items i.e. argument 31
	
	if(24<=additionalInformation && additionalInformation<=27)
		argumentSize <<= additionalInformation - 24;//If argumentSize>23, the rest is relevant, if it's that or under, it's actually the entire argument.
	else
		return [(additionalInformation)];
	
	startingPoint++;
	
	return includeAdditional ? [additionalInformation] : [] ~ sourceArray[startingPoint .. startingPoint+argumentSize];
}

DataItem getCBORByteString(ref ubyte[] sourceArray, ulong startingPoint=0){
	/++
	Get CBOR Byte String.
	Warning: This function does not yet support infinite length items
	+/
	ubyte[] array=_getCBORArgument(sourceArray, startingPoint);
	ulong stringLength=getUnsignedFromCBOR(array, 0);
	//startingPoint+=;
	//delete array;
	
	return DataItem(sourceArray[++startingPoint .. startingPoint+stringLength]);
}

DataItem getCBORString(ref ubyte[] sourceArray, ulong startingPoint=0){
	import std.string : assumeUTF;
	return DataItem(assumeUTF(getCBORByteString(sourceArray, startingPoint)._bin_str));//TODO: MAke this more efficient by use an intermediary function for these two.
}

DataItem fromCBOR(ubyte[] sourceArray, bool strict=false);

ulong _getCBORListByteLength(ref ubyte[] sourceArray, ulong startingPoint){
	ulong elementCount=sourceArray[startingPoint] & 31;
	return 0;//TODO: Implement or delete
}

DataItem getDeepestLastItem(ref DataItem[] array){
	ulong i=0;
	bool atEnd=false;
	DataItem currentElement;
	while(!atEnd){
		if(currentElement.last()._type==DataType.List)
			currentElement=currentElement.last();
		else
			return currentElement;
	}
	
	import core.exception : UnicodeException;//TODO Replace with real exceptions
	throw new Exception("BYE");
}

DataItem getCBORList(ref ubyte[] sourceArray, ulong startingPoint=0){
	import std.range : popBack;
	DataItem[] items;
	ubyte[] argument=_getCBORArgument(sourceArray, startingPoint, true);
	ulong itemIndex=0, itemDepth=0, index=startingPoint, length=getUnsignedFromCBOR(argument);
	ulong[] depthList=[length];
	
	index++;
	debug{import std.stdio;}
	
	while(itemIndex<length){
		ubyte itemType=sourceArray[index] >> 5;
		
		argument=_getCBORArgument(sourceArray, index, true);
		ulong argumentValue=getUnsignedFromCBOR(argument);
		
		final switch(itemType){
			case 0:
			case 1:
				items~=DataItem(argumentValue);
				index+=argument.length;
				break;//TODO: REmove
			case 2://TODO
			case 3:
				items~=getCBORString(sourceArray, index);
				index+=argument.length+argumentValue;
				break;
			case 4://TODO
			case 5://TODO
			case 6:
			case 7:
				depthList~=argumentValue;//lengh would make most sense, total count is easier to keep track of though
				length+=argumentValue;
				index+=argument.length;
				DataItem[] d;
				items~=DataItem(d);
				//goto endloop;
			//default:
			//	break;
		}
		itemIndex++;
		if(depthList.length && depthList[$-1]==0)
			depthList.popBack();//:)
		debug{writeln("Depth: ", depthList);}
		debug{writeln(itemIndex, "/", length, ": ", index);}
	}
	return DataItem(items);
}

DataItem unpackMap(ref ubyte[] sourceArray){
	//TODO: Implement
	return DataItem();
}

DataItem fromCBOR(ubyte[] sourceArray, bool strict=false){//Refactor: Clean this up, get rid of recursion.

	import std.math : pow;
	import std.conv : ConvException, to;
	DataType t;
	DataItem[] list;

	uint major=sourceArray[0] >> 5;//Major type is first 3 bits of the first argument
	ubyte[] argument=_getCBORArgument(sourceArray);
	switch(major){
		case 0:
		case 1:
			return DataItem(getUnsignedFromCBOR(sourceArray, 0)+major, major ? DataType.NegativeInteger : DataType.UnsignedInteger);
		case 2:
			return getCBORByteString(sourceArray);
		case 3:
			return getCBORString(sourceArray);//DataItem();//TODO
		case 4:
			return getCBORList(sourceArray);
		case 5:
			DataItem item=list;
			return item;
		default:
			return DataItem(0);//TODO: Change ASAP
	}
	//debug{writeln(array);}
	return DataItem();//TODO Put an exception here?
}

int main(){
	import std.stdio;;
	writeln(fromCBOR([21]));
	writeln("Number: ", fromCBOR([24, 94]));//94
	writeln("Number: ", fromCBOR([24, 12]));//12
	writeln("Number 256: ", fromCBOR([25, 1, 0]));//256
	writeln("Number: ", fromCBOR([56, 255]));//-256
	writeln("Number: ", fromCBOR([57, 1, 98]));//-355
	writeln("Number 190055: ", fromCBOR([26, 0, 2, 230, 103]));//190055
	writeln("\"Hello world!\"", fromCBOR([108, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 33]));//"Hello world!"
	writeln("Output: ",fromCBOR([112, 87, 111, 114, 107, 105, 110, 103, 33, 32, 45, 46, 94, 32, 49, 50, 51]));//"Working! -.^ 123"
	writeln("Number 12860: ", fromCBOR([25, 50, 60]));
	writeln(fromCBOR([25, 70, 1]));
	writeln("From array: ", fromCBOR([131, 101, 104, 101, 108, 108, 111, 105, 77, 121, 32, 102, 114, 105, 101, 110, 100, 24, 1]));//"hello", "My friend", 1
	writeln("From map: ", fromCBOR([162, 97, 49, 104, 109, 97, 112, 32, 116, 101, 115, 116, 101, 104, 101, 108, 108, 111, 105, 77, 121, 32, 102, 114, 105, 101, 110, 100])); // {"hello":"My friend", 1:"map test"}
	writeln("From nested array: ", fromCBOR([132, 101, 104, 101, 108, 108, 111, 105, 77, 121, 32, 102, 114, 105, 101, 110, 100, 1, 130, 104, 101, 109, 98, 101, 100, 100, 101, 100, 1])); // ["hello", "My friend", 1, ["embedded", 1]]
	writeln("[1, 2, \"three\", 4, \"5\"]: ", fromCBOR([133, 1, 2, 101, 116, 104, 114, 101, 101, 4, 97, 53]));
	writeln("[1337, \"L337\"]", fromCBOR([130, 25, 5, 57, 100, 49, 51, 51, 55]));
	return 0;
}
