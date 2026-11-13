// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'recent_reel.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RecentReel {

 String get id;/// The caption's first line, shown in the list.
 String get title; String get videoPath; String get thumbnailPath;@JsonKey(name: 'durationMs')@MillisecondsConverter() Duration get duration;/// The MP4's frame size, shown on Done.
@JsonKey(readValue: readWholeObject)@_OutputSizeConverter() OutputSize get size; DateTime get createdAt;/// The fingerprint of the video it was rendered from.
 String get sourceVideoId;/// The YouTube video a joined link clip came from; null otherwise.
 String? get youtubeId;/// What it used of its source, in source order (spec FR-44).
@_SourceRangesConverter() List<SourceRange> get usedRanges;
/// Create a copy of RecentReel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecentReelCopyWith<RecentReel> get copyWith => _$RecentReelCopyWithImpl<RecentReel>(this as RecentReel, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RecentReel;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecentReel&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.videoPath, _this.videoPath) || other.videoPath == _this.videoPath)&&(identical(other.thumbnailPath, _this.thumbnailPath) || other.thumbnailPath == _this.thumbnailPath)&&(identical(other.duration, _this.duration) || other.duration == _this.duration)&&(identical(other.size, _this.size) || other.size == _this.size)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.sourceVideoId, _this.sourceVideoId) || other.sourceVideoId == _this.sourceVideoId)&&(identical(other.youtubeId, _this.youtubeId) || other.youtubeId == _this.youtubeId)&&const DeepCollectionEquality().equals(other.usedRanges, _this.usedRanges));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as RecentReel;
  return Object.hash(runtimeType,_this.id,_this.title,_this.videoPath,_this.thumbnailPath,_this.duration,_this.size,_this.createdAt,_this.sourceVideoId,_this.youtubeId,const DeepCollectionEquality().hash(_this.usedRanges));
}

@override
String toString() {
  final _this = this as RecentReel;
  return 'RecentReel(id: ${_this.id}, title: ${_this.title}, videoPath: ${_this.videoPath}, thumbnailPath: ${_this.thumbnailPath}, duration: ${_this.duration}, size: ${_this.size}, createdAt: ${_this.createdAt}, sourceVideoId: ${_this.sourceVideoId}, youtubeId: ${_this.youtubeId}, usedRanges: ${_this.usedRanges})';
}


}

/// @nodoc
abstract mixin class $RecentReelCopyWith<$Res>  {
  factory $RecentReelCopyWith(RecentReel value, $Res Function(RecentReel) _then) = _$RecentReelCopyWithImpl;
@useResult
$Res call({
 String id, String title, String videoPath, String thumbnailPath,@JsonKey(name: 'durationMs')@MillisecondsConverter() Duration duration,@JsonKey(readValue: readWholeObject)@_OutputSizeConverter() OutputSize size, DateTime createdAt, String sourceVideoId, String? youtubeId,@_SourceRangesConverter() List<SourceRange> usedRanges
});




}
/// @nodoc
class _$RecentReelCopyWithImpl<$Res>
    implements $RecentReelCopyWith<$Res> {
  _$RecentReelCopyWithImpl(this._self, this._then);

  final RecentReel _self;
  final $Res Function(RecentReel) _then;

/// Create a copy of RecentReel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? videoPath = null,Object? thumbnailPath = null,Object? duration = null,Object? size = null,Object? createdAt = null,Object? sourceVideoId = null,Object? youtubeId = freezed,Object? usedRanges = null,}) {
  return _then(RecentReel(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,videoPath: null == videoPath ? _self.videoPath : videoPath // ignore: cast_nullable_to_non_nullable
as String,thumbnailPath: null == thumbnailPath ? _self.thumbnailPath : thumbnailPath // ignore: cast_nullable_to_non_nullable
as String,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as OutputSize,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,sourceVideoId: null == sourceVideoId ? _self.sourceVideoId : sourceVideoId // ignore: cast_nullable_to_non_nullable
as String,youtubeId: freezed == youtubeId ? _self.youtubeId : youtubeId // ignore: cast_nullable_to_non_nullable
as String?,usedRanges: null == usedRanges ? _self.usedRanges : usedRanges // ignore: cast_nullable_to_non_nullable
as List<SourceRange>,
  ));
}

}


/// Adds pattern-matching-related methods to [RecentReel].
extension RecentReelPatterns on RecentReel {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RecentReel value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RecentReel() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RecentReel value)  $default,){
final _that = this;
switch (_that) {
case _RecentReel():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RecentReel value)?  $default,){
final _that = this;
switch (_that) {
case _RecentReel() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  String videoPath,  String thumbnailPath, @JsonKey(name: 'durationMs')@MillisecondsConverter()  Duration duration, @JsonKey(readValue: readWholeObject)@_OutputSizeConverter()  OutputSize size,  DateTime createdAt,  String sourceVideoId,  String? youtubeId, @_SourceRangesConverter()  List<SourceRange> usedRanges)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RecentReel() when $default != null:
return $default(_that.id,_that.title,_that.videoPath,_that.thumbnailPath,_that.duration,_that.size,_that.createdAt,_that.sourceVideoId,_that.youtubeId,_that.usedRanges);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  String videoPath,  String thumbnailPath, @JsonKey(name: 'durationMs')@MillisecondsConverter()  Duration duration, @JsonKey(readValue: readWholeObject)@_OutputSizeConverter()  OutputSize size,  DateTime createdAt,  String sourceVideoId,  String? youtubeId, @_SourceRangesConverter()  List<SourceRange> usedRanges)  $default,) {final _that = this;
switch (_that) {
case _RecentReel():
return $default(_that.id,_that.title,_that.videoPath,_that.thumbnailPath,_that.duration,_that.size,_that.createdAt,_that.sourceVideoId,_that.youtubeId,_that.usedRanges);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  String videoPath,  String thumbnailPath, @JsonKey(name: 'durationMs')@MillisecondsConverter()  Duration duration, @JsonKey(readValue: readWholeObject)@_OutputSizeConverter()  OutputSize size,  DateTime createdAt,  String sourceVideoId,  String? youtubeId, @_SourceRangesConverter()  List<SourceRange> usedRanges)?  $default,) {final _that = this;
switch (_that) {
case _RecentReel() when $default != null:
return $default(_that.id,_that.title,_that.videoPath,_that.thumbnailPath,_that.duration,_that.size,_that.createdAt,_that.sourceVideoId,_that.youtubeId,_that.usedRanges);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(createToJson: false)
class _RecentReel extends RecentReel {
  const _RecentReel({required this.id, required this.title, required this.videoPath, required this.thumbnailPath, @JsonKey(name: 'durationMs')@MillisecondsConverter() required this.duration, @JsonKey(readValue: readWholeObject)@_OutputSizeConverter() required this.size, required this.createdAt, required this.sourceVideoId, this.youtubeId, @_SourceRangesConverter() required  List<SourceRange> usedRanges}): _usedRanges = usedRanges,super._();
  factory _RecentReel.fromJson(Map<String, dynamic> json) => _$RecentReelFromJson(json);

@override final  String id;
/// The caption's first line, shown in the list.
@override final  String title;
@override final  String videoPath;
@override final  String thumbnailPath;
@override@JsonKey(name: 'durationMs')@MillisecondsConverter() final  Duration duration;
/// The MP4's frame size, shown on Done.
@override@JsonKey(readValue: readWholeObject)@_OutputSizeConverter() final  OutputSize size;
@override final  DateTime createdAt;
/// The fingerprint of the video it was rendered from.
@override final  String sourceVideoId;
/// The YouTube video a joined link clip came from; null otherwise.
@override final  String? youtubeId;
/// What it used of its source, in source order (spec FR-44).
 final  List<SourceRange> _usedRanges;
/// What it used of its source, in source order (spec FR-44).
@override@_SourceRangesConverter() List<SourceRange> get usedRanges {
  if (_usedRanges is EqualUnmodifiableListView) return _usedRanges;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_usedRanges);
}


/// Create a copy of RecentReel
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecentReelCopyWith<_RecentReel> get copyWith => __$RecentReelCopyWithImpl<_RecentReel>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RecentReel&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.videoPath, videoPath) || other.videoPath == videoPath)&&(identical(other.thumbnailPath, thumbnailPath) || other.thumbnailPath == thumbnailPath)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.size, size) || other.size == size)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.sourceVideoId, sourceVideoId) || other.sourceVideoId == sourceVideoId)&&(identical(other.youtubeId, youtubeId) || other.youtubeId == youtubeId)&&const DeepCollectionEquality().equals(other.usedRanges, _usedRanges));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,title,videoPath,thumbnailPath,duration,size,createdAt,sourceVideoId,youtubeId,const DeepCollectionEquality().hash(_usedRanges));
}

@override
String toString() {
    return 'RecentReel(id: $id, title: $title, videoPath: $videoPath, thumbnailPath: $thumbnailPath, duration: $duration, size: $size, createdAt: $createdAt, sourceVideoId: $sourceVideoId, youtubeId: $youtubeId, usedRanges: $usedRanges)';
}


}

/// @nodoc
abstract mixin class _$RecentReelCopyWith<$Res> implements $RecentReelCopyWith<$Res> {
  factory _$RecentReelCopyWith(_RecentReel value, $Res Function(_RecentReel) _then) = __$RecentReelCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String videoPath, String thumbnailPath,@JsonKey(name: 'durationMs')@MillisecondsConverter() Duration duration,@JsonKey(readValue: readWholeObject)@_OutputSizeConverter() OutputSize size, DateTime createdAt, String sourceVideoId, String? youtubeId,@_SourceRangesConverter() List<SourceRange> usedRanges
});




}
/// @nodoc
class __$RecentReelCopyWithImpl<$Res>
    implements _$RecentReelCopyWith<$Res> {
  __$RecentReelCopyWithImpl(this._self, this._then);

  final _RecentReel _self;
  final $Res Function(_RecentReel) _then;

/// Create a copy of RecentReel
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? videoPath = null,Object? thumbnailPath = null,Object? duration = null,Object? size = null,Object? createdAt = null,Object? sourceVideoId = null,Object? youtubeId = freezed,Object? usedRanges = null,}) {
  return _then(_RecentReel(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,videoPath: null == videoPath ? _self.videoPath : videoPath // ignore: cast_nullable_to_non_nullable
as String,thumbnailPath: null == thumbnailPath ? _self.thumbnailPath : thumbnailPath // ignore: cast_nullable_to_non_nullable
as String,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as OutputSize,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,sourceVideoId: null == sourceVideoId ? _self.sourceVideoId : sourceVideoId // ignore: cast_nullable_to_non_nullable
as String,youtubeId: freezed == youtubeId ? _self.youtubeId : youtubeId // ignore: cast_nullable_to_non_nullable
as String?,usedRanges: null == usedRanges ? _self._usedRanges : usedRanges // ignore: cast_nullable_to_non_nullable
as List<SourceRange>,
  ));
}


}

// dart format on
