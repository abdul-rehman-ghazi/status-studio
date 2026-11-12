// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'source_video.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SourceVideo {

 String get videoId; String get title;@JsonKey(name: 'durationMs')@MillisecondsConverter() Duration get duration;/// The earliest a clip can start: where the picture begins, rounded up
/// to a tenth of a second (spec FR-5, M41). A video saved before M41
/// has none, so it reads as zero.
@JsonKey(name: 'pictureStartMs')@MillisecondsConverter() Duration get pictureStart;
/// Create a copy of SourceVideo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourceVideoCopyWith<SourceVideo> get copyWith => _$SourceVideoCopyWithImpl<SourceVideo>(this as SourceVideo, _$identity);

  /// Serializes this SourceVideo to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as SourceVideo;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourceVideo&&(identical(other.videoId, _this.videoId) || other.videoId == _this.videoId)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.duration, _this.duration) || other.duration == _this.duration)&&(identical(other.pictureStart, _this.pictureStart) || other.pictureStart == _this.pictureStart));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SourceVideo;
  return Object.hash(runtimeType,_this.videoId,_this.title,_this.duration,_this.pictureStart);
}

@override
String toString() {
  final _this = this as SourceVideo;
  return 'SourceVideo(videoId: ${_this.videoId}, title: ${_this.title}, duration: ${_this.duration}, pictureStart: ${_this.pictureStart})';
}


}

/// @nodoc
abstract mixin class $SourceVideoCopyWith<$Res>  {
  factory $SourceVideoCopyWith(SourceVideo value, $Res Function(SourceVideo) _then) = _$SourceVideoCopyWithImpl;
@useResult
$Res call({
 String videoId, String title,@JsonKey(name: 'durationMs')@MillisecondsConverter() Duration duration,@JsonKey(name: 'pictureStartMs')@MillisecondsConverter() Duration pictureStart
});




}
/// @nodoc
class _$SourceVideoCopyWithImpl<$Res>
    implements $SourceVideoCopyWith<$Res> {
  _$SourceVideoCopyWithImpl(this._self, this._then);

  final SourceVideo _self;
  final $Res Function(SourceVideo) _then;

/// Create a copy of SourceVideo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? videoId = null,Object? title = null,Object? duration = null,Object? pictureStart = null,}) {
  return _then(SourceVideo(
videoId: null == videoId ? _self.videoId : videoId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration,pictureStart: null == pictureStart ? _self.pictureStart : pictureStart // ignore: cast_nullable_to_non_nullable
as Duration,
  ));
}

}


/// Adds pattern-matching-related methods to [SourceVideo].
extension SourceVideoPatterns on SourceVideo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SourceVideo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SourceVideo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SourceVideo value)  $default,){
final _that = this;
switch (_that) {
case _SourceVideo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SourceVideo value)?  $default,){
final _that = this;
switch (_that) {
case _SourceVideo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String videoId,  String title, @JsonKey(name: 'durationMs')@MillisecondsConverter()  Duration duration, @JsonKey(name: 'pictureStartMs')@MillisecondsConverter()  Duration pictureStart)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SourceVideo() when $default != null:
return $default(_that.videoId,_that.title,_that.duration,_that.pictureStart);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String videoId,  String title, @JsonKey(name: 'durationMs')@MillisecondsConverter()  Duration duration, @JsonKey(name: 'pictureStartMs')@MillisecondsConverter()  Duration pictureStart)  $default,) {final _that = this;
switch (_that) {
case _SourceVideo():
return $default(_that.videoId,_that.title,_that.duration,_that.pictureStart);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String videoId,  String title, @JsonKey(name: 'durationMs')@MillisecondsConverter()  Duration duration, @JsonKey(name: 'pictureStartMs')@MillisecondsConverter()  Duration pictureStart)?  $default,) {final _that = this;
switch (_that) {
case _SourceVideo() when $default != null:
return $default(_that.videoId,_that.title,_that.duration,_that.pictureStart);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SourceVideo implements SourceVideo {
  const _SourceVideo({required this.videoId, required this.title, @JsonKey(name: 'durationMs')@MillisecondsConverter() required this.duration, @JsonKey(name: 'pictureStartMs')@MillisecondsConverter() this.pictureStart = Duration.zero});
  factory _SourceVideo.fromJson(Map<String, dynamic> json) => _$SourceVideoFromJson(json);

@override final  String videoId;
@override final  String title;
@override@JsonKey(name: 'durationMs')@MillisecondsConverter() final  Duration duration;
/// The earliest a clip can start: where the picture begins, rounded up
/// to a tenth of a second (spec FR-5, M41). A video saved before M41
/// has none, so it reads as zero.
@override@JsonKey(name: 'pictureStartMs')@MillisecondsConverter() final  Duration pictureStart;

/// Create a copy of SourceVideo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SourceVideoCopyWith<_SourceVideo> get copyWith => __$SourceVideoCopyWithImpl<_SourceVideo>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SourceVideoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SourceVideo&&(identical(other.videoId, videoId) || other.videoId == videoId)&&(identical(other.title, title) || other.title == title)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.pictureStart, pictureStart) || other.pictureStart == pictureStart));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,videoId,title,duration,pictureStart);
}

@override
String toString() {
    return 'SourceVideo(videoId: $videoId, title: $title, duration: $duration, pictureStart: $pictureStart)';
}


}

/// @nodoc
abstract mixin class _$SourceVideoCopyWith<$Res> implements $SourceVideoCopyWith<$Res> {
  factory _$SourceVideoCopyWith(_SourceVideo value, $Res Function(_SourceVideo) _then) = __$SourceVideoCopyWithImpl;
@override @useResult
$Res call({
 String videoId, String title,@JsonKey(name: 'durationMs')@MillisecondsConverter() Duration duration,@JsonKey(name: 'pictureStartMs')@MillisecondsConverter() Duration pictureStart
});




}
/// @nodoc
class __$SourceVideoCopyWithImpl<$Res>
    implements _$SourceVideoCopyWith<$Res> {
  __$SourceVideoCopyWithImpl(this._self, this._then);

  final _SourceVideo _self;
  final $Res Function(_SourceVideo) _then;

/// Create a copy of SourceVideo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? videoId = null,Object? title = null,Object? duration = null,Object? pictureStart = null,}) {
  return _then(_SourceVideo(
videoId: null == videoId ? _self.videoId : videoId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration,pictureStart: null == pictureStart ? _self.pictureStart : pictureStart // ignore: cast_nullable_to_non_nullable
as Duration,
  ));
}


}

// dart format on
