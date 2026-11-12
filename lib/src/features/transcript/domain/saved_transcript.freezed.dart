// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'saved_transcript.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SavedTranscript implements DiagnosticableTreeMixin {

@JsonKey(readValue: readWholeObject)@_TranscriptConverter() Transcript get transcript;/// `groq-whisper-large-v3` (older scripts: `groq-whisper-large-v3-turbo`)
/// or `edited`.
 String get source; DateTime get savedAt;
/// Create a copy of SavedTranscript
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SavedTranscriptCopyWith<SavedTranscript> get copyWith => _$SavedTranscriptCopyWithImpl<SavedTranscript>(this as SavedTranscript, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  final _this = this as SavedTranscript;
  properties
    ..add(DiagnosticsProperty('type', 'SavedTranscript'))
    ..add(DiagnosticsProperty('transcript', _this.transcript))..add(DiagnosticsProperty('source', _this.source))..add(DiagnosticsProperty('savedAt', _this.savedAt));
}



@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  final _this = this as SavedTranscript;
  return 'SavedTranscript(transcript: ${_this.transcript}, source: ${_this.source}, savedAt: ${_this.savedAt})';
}


}

/// @nodoc
abstract mixin class $SavedTranscriptCopyWith<$Res>  {
  factory $SavedTranscriptCopyWith(SavedTranscript value, $Res Function(SavedTranscript) _then) = _$SavedTranscriptCopyWithImpl;
@useResult
$Res call({
@JsonKey(readValue: readWholeObject)@_TranscriptConverter() Transcript transcript, String source, DateTime savedAt
});




}
/// @nodoc
class _$SavedTranscriptCopyWithImpl<$Res>
    implements $SavedTranscriptCopyWith<$Res> {
  _$SavedTranscriptCopyWithImpl(this._self, this._then);

  final SavedTranscript _self;
  final $Res Function(SavedTranscript) _then;

/// Create a copy of SavedTranscript
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? transcript = null,Object? source = null,Object? savedAt = null,}) {
  return _then(SavedTranscript(
transcript: null == transcript ? _self.transcript : transcript // ignore: cast_nullable_to_non_nullable
as Transcript,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,savedAt: null == savedAt ? _self.savedAt : savedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [SavedTranscript].
extension SavedTranscriptPatterns on SavedTranscript {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SavedTranscript value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SavedTranscript() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SavedTranscript value)  $default,){
final _that = this;
switch (_that) {
case _SavedTranscript():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SavedTranscript value)?  $default,){
final _that = this;
switch (_that) {
case _SavedTranscript() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(readValue: readWholeObject)@_TranscriptConverter()  Transcript transcript,  String source,  DateTime savedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SavedTranscript() when $default != null:
return $default(_that.transcript,_that.source,_that.savedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(readValue: readWholeObject)@_TranscriptConverter()  Transcript transcript,  String source,  DateTime savedAt)  $default,) {final _that = this;
switch (_that) {
case _SavedTranscript():
return $default(_that.transcript,_that.source,_that.savedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(readValue: readWholeObject)@_TranscriptConverter()  Transcript transcript,  String source,  DateTime savedAt)?  $default,) {final _that = this;
switch (_that) {
case _SavedTranscript() when $default != null:
return $default(_that.transcript,_that.source,_that.savedAt);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(createToJson: false)
class _SavedTranscript extends SavedTranscript with DiagnosticableTreeMixin {
  const _SavedTranscript({@JsonKey(readValue: readWholeObject)@_TranscriptConverter() required this.transcript, required this.source, required this.savedAt}): super._();
  factory _SavedTranscript.fromJson(Map<String, dynamic> json) => _$SavedTranscriptFromJson(json);

@override@JsonKey(readValue: readWholeObject)@_TranscriptConverter() final  Transcript transcript;
/// `groq-whisper-large-v3` (older scripts: `groq-whisper-large-v3-turbo`)
/// or `edited`.
@override final  String source;
@override final  DateTime savedAt;

/// Create a copy of SavedTranscript
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SavedTranscriptCopyWith<_SavedTranscript> get copyWith => __$SavedTranscriptCopyWithImpl<_SavedTranscript>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'SavedTranscript'))
    ..add(DiagnosticsProperty('transcript', transcript))..add(DiagnosticsProperty('source', source))..add(DiagnosticsProperty('savedAt', savedAt));
}



@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'SavedTranscript(transcript: $transcript, source: $source, savedAt: $savedAt)';
}


}

/// @nodoc
abstract mixin class _$SavedTranscriptCopyWith<$Res> implements $SavedTranscriptCopyWith<$Res> {
  factory _$SavedTranscriptCopyWith(_SavedTranscript value, $Res Function(_SavedTranscript) _then) = __$SavedTranscriptCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(readValue: readWholeObject)@_TranscriptConverter() Transcript transcript, String source, DateTime savedAt
});




}
/// @nodoc
class __$SavedTranscriptCopyWithImpl<$Res>
    implements _$SavedTranscriptCopyWith<$Res> {
  __$SavedTranscriptCopyWithImpl(this._self, this._then);

  final _SavedTranscript _self;
  final $Res Function(_SavedTranscript) _then;

/// Create a copy of SavedTranscript
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? transcript = null,Object? source = null,Object? savedAt = null,}) {
  return _then(_SavedTranscript(
transcript: null == transcript ? _self.transcript : transcript // ignore: cast_nullable_to_non_nullable
as Transcript,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,savedAt: null == savedAt ? _self.savedAt : savedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}


/// @nodoc
mixin _$PartialTranscript implements DiagnosticableTreeMixin {

 int get completedChunks;@_TranscriptLineConverter() List<TranscriptLine> get lines;
/// Create a copy of PartialTranscript
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PartialTranscriptCopyWith<PartialTranscript> get copyWith => _$PartialTranscriptCopyWithImpl<PartialTranscript>(this as PartialTranscript, _$identity);

  /// Serializes this PartialTranscript to a JSON map.
  Map<String, dynamic> toJson();

@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  final _this = this as PartialTranscript;
  properties
    ..add(DiagnosticsProperty('type', 'PartialTranscript'))
    ..add(DiagnosticsProperty('completedChunks', _this.completedChunks))..add(DiagnosticsProperty('lines', _this.lines));
}

@override
bool operator ==(Object other) {
  final _this = this as PartialTranscript;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PartialTranscript&&(identical(other.completedChunks, _this.completedChunks) || other.completedChunks == _this.completedChunks)&&const DeepCollectionEquality().equals(other.lines, _this.lines));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PartialTranscript;
  return Object.hash(runtimeType,_this.completedChunks,const DeepCollectionEquality().hash(_this.lines));
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  final _this = this as PartialTranscript;
  return 'PartialTranscript(completedChunks: ${_this.completedChunks}, lines: ${_this.lines})';
}


}

/// @nodoc
abstract mixin class $PartialTranscriptCopyWith<$Res>  {
  factory $PartialTranscriptCopyWith(PartialTranscript value, $Res Function(PartialTranscript) _then) = _$PartialTranscriptCopyWithImpl;
@useResult
$Res call({
 int completedChunks,@_TranscriptLineConverter() List<TranscriptLine> lines
});




}
/// @nodoc
class _$PartialTranscriptCopyWithImpl<$Res>
    implements $PartialTranscriptCopyWith<$Res> {
  _$PartialTranscriptCopyWithImpl(this._self, this._then);

  final PartialTranscript _self;
  final $Res Function(PartialTranscript) _then;

/// Create a copy of PartialTranscript
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? completedChunks = null,Object? lines = null,}) {
  return _then(PartialTranscript(
completedChunks: null == completedChunks ? _self.completedChunks : completedChunks // ignore: cast_nullable_to_non_nullable
as int,lines: null == lines ? _self.lines : lines // ignore: cast_nullable_to_non_nullable
as List<TranscriptLine>,
  ));
}

}


/// Adds pattern-matching-related methods to [PartialTranscript].
extension PartialTranscriptPatterns on PartialTranscript {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PartialTranscript value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PartialTranscript() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PartialTranscript value)  $default,){
final _that = this;
switch (_that) {
case _PartialTranscript():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PartialTranscript value)?  $default,){
final _that = this;
switch (_that) {
case _PartialTranscript() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int completedChunks, @_TranscriptLineConverter()  List<TranscriptLine> lines)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PartialTranscript() when $default != null:
return $default(_that.completedChunks,_that.lines);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int completedChunks, @_TranscriptLineConverter()  List<TranscriptLine> lines)  $default,) {final _that = this;
switch (_that) {
case _PartialTranscript():
return $default(_that.completedChunks,_that.lines);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int completedChunks, @_TranscriptLineConverter()  List<TranscriptLine> lines)?  $default,) {final _that = this;
switch (_that) {
case _PartialTranscript() when $default != null:
return $default(_that.completedChunks,_that.lines);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PartialTranscript with DiagnosticableTreeMixin implements PartialTranscript {
  const _PartialTranscript({required this.completedChunks, @_TranscriptLineConverter() required  List<TranscriptLine> lines}): _lines = lines;
  factory _PartialTranscript.fromJson(Map<String, dynamic> json) => _$PartialTranscriptFromJson(json);

@override final  int completedChunks;
 final  List<TranscriptLine> _lines;
@override@_TranscriptLineConverter() List<TranscriptLine> get lines {
  if (_lines is EqualUnmodifiableListView) return _lines;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_lines);
}


/// Create a copy of PartialTranscript
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PartialTranscriptCopyWith<_PartialTranscript> get copyWith => __$PartialTranscriptCopyWithImpl<_PartialTranscript>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PartialTranscriptToJson(this, );
}
@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'PartialTranscript'))
    ..add(DiagnosticsProperty('completedChunks', completedChunks))..add(DiagnosticsProperty('lines', lines));
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PartialTranscript&&(identical(other.completedChunks, completedChunks) || other.completedChunks == completedChunks)&&const DeepCollectionEquality().equals(other.lines, _lines));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,completedChunks,const DeepCollectionEquality().hash(_lines));
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'PartialTranscript(completedChunks: $completedChunks, lines: $lines)';
}


}

/// @nodoc
abstract mixin class _$PartialTranscriptCopyWith<$Res> implements $PartialTranscriptCopyWith<$Res> {
  factory _$PartialTranscriptCopyWith(_PartialTranscript value, $Res Function(_PartialTranscript) _then) = __$PartialTranscriptCopyWithImpl;
@override @useResult
$Res call({
 int completedChunks,@_TranscriptLineConverter() List<TranscriptLine> lines
});




}
/// @nodoc
class __$PartialTranscriptCopyWithImpl<$Res>
    implements _$PartialTranscriptCopyWith<$Res> {
  __$PartialTranscriptCopyWithImpl(this._self, this._then);

  final _PartialTranscript _self;
  final $Res Function(_PartialTranscript) _then;

/// Create a copy of PartialTranscript
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? completedChunks = null,Object? lines = null,}) {
  return _then(_PartialTranscript(
completedChunks: null == completedChunks ? _self.completedChunks : completedChunks // ignore: cast_nullable_to_non_nullable
as int,lines: null == lines ? _self._lines : lines // ignore: cast_nullable_to_non_nullable
as List<TranscriptLine>,
  ));
}


}

// dart format on
