#--
# Copyright (c) 2010 Wang Yong
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

###############################################
# CStruct
# Author: Wang Yong (skandhas)
# CStruct Homepage: cstruct.rubyforge.org
# E-Mail: skandhas@163.com
###############################################

require 'enumerator'

class CStruct
  
  VERSION = '1.0.0'

public 
  def self.options opt_hash
  	raise 'Data Type Error!' unless opt_hash.is_a? Hash
  	@endian = opt_hash[:endian] if opt_hash.has_key?:endian
  	raise 'Unsupported Endian!' if @endian!=:little and @endian!=:big
  	@align  = opt_hash[:align]  if opt_hash.has_key?:align
  end
  	
  def self.endian
    @endian  
  end
  
  def self.align
    @align 
  end
  
  def self.field_hash
  	@fields
  end
  
private   

  def self.init_class_var  
    @size   = 0
    @fields = {}
    @endian = :little # :little or :big
    @align  = 1 # Unsupport in this version
  end  
  		
  def self.field symbol,fsize,fsign,dimension = nil
    if dimension.is_a? Array
      do_arrayfield  symbol,fsize,fsign,dimension
    else
      do_field symbol,fsize,fsign
    end      
  end
  
  def self.structfield  symbol,sclass,ssize,dimension = nil
    if dimension.is_a? Array
      do_arraystructfield  symbol,sclass,ssize,dimension 
    else
      do_structfield symbol,sclass,ssize
    end      
  end  
  
  def self.inherited clazz
      clazz.init_class_var
  end
    
  def self.method_missing(method, *args)
    sclass = method_to_class_by_class self,method
    sclass = method_to_class_by_class Object,method unless sclass
	sclass = method_to_class_by_namespace method unless sclass
	sclass = method_to_class method unless sclass
    super unless sclass 
    is_cstruct = sclass.ancestors.select{|x| x == CStruct } 
     if  is_cstruct
        symbol,dimension = *args
        structfield symbol,sclass,sclass.size,dimension
     else
      super
     end
  end
  
  def  self.method_to_class_by_class clazz,method
    in_object_class = false
    if RUBY_VERSION < '1.9' 
        in_object_class = clazz.constants.include? method.to_s
    else
        in_object_class = clazz.constants.include? method
    end
    return nil unless in_object_class
    clazz.const_get method
  end
  
  
  # X::Y::A
  def self.method_to_class_by_namespace method
    sclass = nil
      class_name_array = self.to_s.split('::')
  	return nil if class_name_array.size < 2
    class_array = []
      class_name_array.pop
      class_name_array.inject(self){|m,class_name| class_array << m.const_get(class_name.to_sym);  class_array.last }
      class_array.reverse_each do |clazz|
        if clazz.const_defined?(method)
          sclass = clazz.const_get(method) 
          break
        end  
      end
  	sclass
    end

  # X_Y_A
  def self.method_to_class  method
     
  	super_namespace = nil	
  	class_name_array = self.to_s.split('::')
  	
  	if class_name_array.size < 2
  		super_namespace = Object
     else
  		class_name_array.pop
  		super_namespace = class_name_array.inject(Object) {|m,class_name| m.const_get(class_name.to_sym) }
     end

  	namespace_name_array = method.to_s.split('_')
  	return nil if namespace_name_array.size < 2
  	sclass = namespace_name_array.inject(super_namespace) {|m,class_name| m.const_get(class_name.to_sym) }
  end
  
  def self.do_field symbol,fsize,fsign
    foffset =  @size
    @size   += fsize
    @fields[symbol] = [fsize,foffset,fsign,nil]
    
    define_method(symbol)       { normal_field_to_value(symbol) }
    define_method("#{symbol}=") { |value| value_to_field(symbol,value) }
  end
  
  def self.do_arrayfield symbol,fsize,fsign,dimension 
    bytesize = fsize * dimension.inject(1){|m,i| m*=i}
    foffset    = @size
    @size      +=  bytesize
    @fields[symbol] = [fsize,foffset,fsign,dimension,bytesize]
    
    define_method(symbol)       {  array_field_to_value(symbol) }
    define_method("#{symbol}=") { |value| value_to_arrayfield(symbol,value) }
  end
  
  def self.do_structfield symbol,sclass,ssize
    foffset =  @size
    @size  +=  ssize
    @fields[symbol] = [ssize,foffset,:ignore,nil]
    
    define_method(symbol)       { struct_field_to_value(symbol,sclass)}
    define_method("#{symbol}=") { |value| value_to_struct_field(symbol,sclass,value)}
  end
  
  def self.do_arraystructfield  symbol,sclass,ssize,dimension 
    bytesize= ssize * dimension.inject(1){|m,i| m*=i}
    foffset    = @size
    @size      +=  bytesize
    @fields[symbol] = [ssize,foffset,:ignore,dimension,bytesize]
    
    define_method(symbol)       { array_struct_field_to_value(symbol,sclass) }
    define_method("#{symbol}=") { |value| value_to_array_struct_field(symbol,sclass,value) }
  end
  
  def self.unsigned symbol,fsize,dimension
      field symbol,fsize,:unsigned,dimension
  end
    
  def self.signed symbol,fsize,dimension
      field symbol,fsize,:signed,dimension
  end

  public 

  def self.size
    @size
  end
  
  class<<self
    alias_method :__size__, :size
    
    [1,2,4,8].each do |i|
      define_method "unsigned_#{i}byte" do |*args| # |symbol,dimension=nil|
        symbol,dimension = args 
        unsigned symbol,i,dimension
      end
      define_method "signed_#{i}byte" do  |*args|  # |symbol,dimension=nil|
         symbol,dimension = args 
         signed symbol,i,dimension
      end
    end 
    
    def float(*args)  # |symbol,dimension=nil|
      symbol,dimension = args
      field symbol,4,:float,dimension  
    end
    def double(*args) # |symbol,dimension=nil|
      symbol,dimension = args
      field symbol,8,:double,dimension
    end
    
    alias uint64  unsigned_8byte
    alias uint32  unsigned_4byte
    alias uint16  unsigned_2byte 
    alias uint8   unsigned_1byte
    alias uchar   unsigned_1byte
    
    alias int64  signed_8byte
    alias int32  signed_4byte
    alias int16  signed_2byte 
    alias int8   signed_1byte
    alias char   signed_1byte  
  end
  
  # call init_class_var
  init_class_var
    
  # module Utils
  module Utils #:nodoc: all
    UnpackFormat =
    {
      :little => { 1=>'C',2=>'v',4=>'V',8=>'Q',:float=>'e',:double=>'E'},
      :big    => { 1=>'C',2=>'n',4=>'N',8=>'Q',:float=>'g',:double=>'G'}, #8=>'Q'? 'Q' is native endian
    }
    SigedMaxValue    = {  1 => 0x7F, 2 => 0x7FFF, 4 => 0x7FFFFFFF, 8 => 0x7FFFFFFFFFFFFFFF }
    UnsigedMaxValue  = {  1 => 0xFF, 2 => 0xFFFF, 4 => 0xFFFFFFFF, 8 => 0xFFFFFFFFFFFFFFFF }
    
    # buffer is a String's object
    def self.unpack buffer,struct_endian,fsize,fsign
      value =nil
      if fsign==:float or fsign ==:double
        format = UnpackFormat[struct_endian][fsign]
        value  = buffer.unpack(format)[0]
      else  
      format = UnpackFormat[struct_endian][fsize]
      value  = buffer.unpack(format)[0]
      if  fsign == :signed
        value = unsigned_to_signed  value,fsize
      end  
      end      
      value
    end
    
    # buffer is a Array's object
    def self.pack buffer,struct_endian,fsize,fsign
      if fsign==:float or fsign ==:double
        format = UnpackFormat[struct_endian][fsign]
      else
      format = UnpackFormat[struct_endian][fsize]
      end 
      buffer.pack format
    end
    
    # dosen't use monkey patch~
    def self.string_setbyte string ,index,value
      if  RUBY_VERSION < "1.9"
        string[index] = value
      else
        string.setbyte index,value
      end        
    end
    def self.string_getbyte string ,index
      if  RUBY_VERSION < "1.9"
        string[index]
      else
        string.getbyte index
      end  
    end
    
    def self.unsigned_to_signed value,value_size
      if value>SigedMaxValue[value_size] 
        ret = value - UnsigedMaxValue[value_size]-1
      else
        ret = value
      end
      
    end
    def self.buffer_setbytes(target,source,targetindex)
        source.enum_for(:each_byte).each_with_index do |byte,index|
        string_setbyte(target,targetindex + index,byte)
      end
    end
  end # module Utils
  
public  
  # instance methods
  attr_accessor:owner
  def initialize
    @data  = "\0"*self.class.size
    @owner = []
    @data.encode!("BINARY") if RUBY_VERSION >= '1.9'
    
    yield self if block_given?
  end
  
  def data
    @data
  end
  
  def reset
    (0...self.class.size).each do |i|
      CStruct::Utils.string_setbyte @data,i, 0
    end
    sync_to_owner
  end
  	
  def data= bindata
    raise 'Data Type Error!' unless bindata.is_a? String
    self << bindata
  end
  
  def << bindata
    count = @data.size < bindata.size ? @data.size : bindata.size
    (0...count).each do |i|
      CStruct::Utils.string_setbyte @data,i, CStruct::Utils.string_getbyte(bindata,i)
    end
  end
    
  def sync_to_owner
    return if @owner.empty?
    final_offset = @owner.inject(0) do |sum,owner_value| 
      _,foffset,_ = owner_value
      sum+= foffset
    end
    onwerdata,_,_ = @owner.last
    CStruct::Utils.buffer_setbytes onwerdata,@data,final_offset
  end
  
  alias __data__  data
  alias __reset__ reset
  alias __data__= data=

private  

  def normal_field_to_value symbol
    make_normal_field(self.class.field_hash[symbol],self.class.endian)
  end
  
  def array_field_to_value symbol
    make_array_normal_field(self.class.field_hash[symbol],self.class.endian)
  end

  def struct_field_to_value symbol,sclass
    make_struct_field(self.class.field_hash[symbol],self.class.endian,sclass)
  end
  def array_struct_field_to_value symbol,sclass
    make_array_struct_field(self.class.field_hash[symbol],self.class.endian,sclass)
  end
  
  def value_to_field symbol,value
    dataref   = @data
    onwerref  = @owner
    self.class.class_eval do
      fsize,foffset,fsign = *@fields[symbol]
      bin_string = CStruct::Utils::pack [value],@endian,fsize,fsign
      CStruct::Utils.buffer_setbytes dataref,bin_string,foffset
    end   
    sync_to_owner
  end
  
  
  def value_to_arrayfield symbol,value
    
    fsize,foffset,fsign,dimension,array_bytesize = *self.class.field_hash[symbol]
    array_length = array_bytesize/fsize
  
    if (fsize==1) && (value.is_a? String)   
      if value.length >= array_length
        puts "WARNING: \"#{value}\".length(#{value.length}) >= #{symbol}.length(#{dimension})!!"
      end  
      value = value[0...array_length-1]
      CStruct::Utils.buffer_setbytes @data,value,foffset
      sync_to_owner
    else 
    raise "No Implement!(CStruct,version:#{CStruct::VERSION})" 
  end
  end
  
  def value_to_struct_field symbol,sclass,value
    raise "No Implement!(CStruct,version:#{CStruct::VERSION})" 
  end
  
  def value_to_array_struct_field symbol,sclass,value
    raise "No Implement!(CStruct,version:#{CStruct::VERSION})" 
  end

  def make_normal_field  finfo,sendian,sclass = nil # finfo =[fsize,foffset,fsign,dimension,array_bytesize]
    fsize,foffset,fsign = finfo
    CStruct::Utils::unpack(@data[foffset,fsize],sendian,fsize,fsign)
  end
  
  def make_struct_field finfo,sendian,sclass  # finfo =[fsize,foffset,fsign,dimension,array_bytesize]
    value     = sclass.new
    ssize,foffset,ignore = finfo
    value <<  @data[foffset,ssize]
    value.owner << [@data,foffset,ssize]
    if self.owner.size > 0
      value.owner += self.owner
    end
    value
  end
  
  def make_array_normal_field finfo,sendian,sclass = nil  # finfo =[fsize,foffset,fsign,dimension,array_bytesize]
    dataref   = @data
    objref    = self
    value = buffer_to_values finfo,sendian
    def value.metaclass  
      class<<self; self; end
    end
    
    value.metaclass.__send__ :define_method,:[]= do |i,v|
      fsize,foffset,fsign = finfo
      bin_string = CStruct::Utils::pack [v],sendian,fsize,fsign
      CStruct::Utils.buffer_setbytes dataref,bin_string,foffset + i * fsize
      objref.sync_to_owner
    end
    
    value.metaclass.__send__ :define_method,:to_cstr  do value.pack("C#{value.index(0)}") end if finfo[0] == 1
    
    if  RUBY_VERSION > "1.9"
    	utf_endian = {:little=>"LE",:big=>"BE"}	
		value.metaclass.__send__ :define_method,:to_wstr do 
			value.pack("S#{value.index(0)}").force_encoding("UTF-16#{utf_endian[sendian]}") 	
		end if finfo[0] == 2
    	
		value.metaclass.__send__ :define_method,:to_wstr do 
			value.pack("L#{value.index(0)}").force_encoding("UTF-32#{utf_endian[sendian]}") 	
		end if finfo[0] == 4	
    end
    
    value
  end
  
  def make_array_struct_field finfo,sendian,sclass  # finfo =[fsize,foffset,fsign,dimension,array_bytesize]
    value = buffer_to_structs finfo,sendian,sclass
  end
  
  def buffer_to_single_value fsize,foffset,iterator,sendian,fsign
    CStruct::Utils::unpack(@data[foffset + iterator * fsize,fsize],sendian,fsize,fsign)
  end
  
  def buffer_to_values finfo,sendian # finfo =[fsize,foffset,fsign,dimension,array_bytesize]
    value =[]
    fsize,foffset,fsign,dimension,bytesize = * finfo
    (0...bytesize/fsize).each do |i|
        value <<  buffer_to_single_value(fsize,foffset,i,sendian,fsign)
    end
    value
  end
  
  def buffer_to_single_struct  sclass,ssize,soffset,iterator,sendian,fsign
    value     = sclass.new
    value <<  @data[soffset + iterator * ssize,ssize]

    value.owner << [@data,soffset + iterator * ssize,ssize]

    if self.owner.size > 0
      value.owner += self.owner
    end   
    value
  end
  
  def buffer_to_structs finfo,sendian,sclass  # finfo =[ssize,soffset,ssign,dimension,array_bytesize]
    value =[]
    ssize,soffset,ssign,dimension,bytesize =  finfo
    (0...bytesize/ssize).each do |i|
        value <<  buffer_to_single_struct(sclass,ssize,soffset,i,sendian,ssign)
      end
    value
  end
end 

def CStruct.union symbol,&block
	union_super  = self.ancestors[1]
	union_class = Class.new(union_super) do
	def self.change_to_union
	    @fields.each do|k,v|
	      v[1] = 0
	      @fields[k] = v
	    end
	    max_field_size = @fields.values.inject(0)do |max,v| 
	      dimension = v[3]
	      dimension_product = 1
	      dimension_product = dimension.inject(1){|m,d| m *= d } if dimension.is_a? Array
	      field_size = v[0]* dimension_product
	      max = (field_size> max ? field_size : max)
	    end
	    @size = max_field_size
	  end
	end	
    union_class.instance_eval(&block) 
    union_class.instance_eval{change_to_union}
    do_structfield symbol,union_class,union_class.size
end

def CStruct.struct symbol,&block
  struct_super  = self.ancestors[1]
  struct_class = Class.new(struct_super) 
  struct_class.instance_eval(&block)
  do_structfield symbol,struct_class,struct_class.size
end
	 
