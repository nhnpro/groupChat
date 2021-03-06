import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:multi_image_picker/multi_image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../utils/colors.dart';
import '../widgets/widgets.dart';
import '../models/userModel.dart';
import '../services/imagesService.dart';
import 'home.dart';

class GroupChat extends StatelessWidget {
  final String threadId;
  final String threadName;
  final UserModel userModel;
  GroupChat(
      {@required this.threadId, @required this.threadName, this.userModel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '$threadName',
          style: TextStyle(color: thirdColor, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: ChatScreen(threadId: threadId, userModel: userModel),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String threadId;
  final UserModel userModel;
  ChatScreen({@required this.threadId, this.userModel});

  @override
  State createState() =>
      ChatScreenState(threadId: threadId, selectedUser: userModel);
}

class ChatScreenState extends State<ChatScreen> {
  ChatScreenState({@required this.threadId, this.selectedUser});

  String threadId;
  UserModel selectedUser;
  String currentUserId;
  String currentUserPhoto;
  String currentUserName;
  bool _isRecording = false;
  String _path;
  StreamSubscription _recorderSubscription;
  StreamSubscription _dbPeakSubscription;
  var listMessage;
  SharedPreferences prefs;
  bool isLoading = false;
  bool isShowSticker = false;
  String imageUrl = '';
  String recordUrl = '';
  String _recorderTxt = '00:00:00';
  String error;
  final TextEditingController textEditingController = TextEditingController();
  final ScrollController listScrollController = ScrollController();
  final FocusNode focusNode = FocusNode();
  FlutterSound flutterSound = FlutterSound();
  ImageServices imageServices;

  @override
  void initState() {
    super.initState();
    focusNode.addListener(onFocusChange);

    readLocal();
    initializeDateFormatting();
  }

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  void onFocusChange() {
    if (focusNode.hasFocus) {
      // Hide sticker when keyboard appear
      setState(() {
        isShowSticker = false;
      });
    }
  }

  readLocal() async {
    prefs = await SharedPreferences.getInstance();
    currentUserId = prefs.getString('id') ?? '';
    currentUserPhoto = prefs.getString('photoUrl');
    currentUserName = prefs.getString('nickname') ?? '';

    imageServices = ImageServices(
        threadId: threadId,
        selectedUser: selectedUser,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        currentUserPhoto: currentUserPhoto);
    setState(() {});
  }

  void getSticker() {
    // Hide keyboard when sticker appear
    focusNode.unfocus();
    setState(() {
      isShowSticker = !isShowSticker;
    });
  }

  _onPickImages() async {
    showModalBottomSheet(
        context: context,
        builder: (builder) {
          return Container(
            height: 150,
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              children: <Widget>[
                Expanded(
                    child: Text(
                  'Select the image source',
                  style: TextStyle(
                      fontSize: 20.0,
                      fontWeight: FontWeight.bold,
                      color: primaryColor),
                )),
                Expanded(
                  child: FlatButton(
                      child: Text(
                        "Camera",
                        style: TextStyle(fontSize: 15.0, color: textColor),
                      ),
                      onPressed: () async {
                        _selectMultibleImage(
                            await imageServices.getImages(cameraEnable: true));
                        Navigator.pop(context);
                      }),
                ),
                Expanded(
                  child: FlatButton(
                      child: Text(
                        "Gallery",
                        style: TextStyle(fontSize: 15.0, color: textColor),
                      ),
                      onPressed: () async {
                        _selectMultibleImage(
                            await imageServices.getImages(cameraEnable: false));
                        Navigator.pop(context);
                      }),
                )
              ],
            ),
          );
        });
  }

  _selectMultibleImage(List<Asset> assestimages) async {
    try {
      //1- open dialog to chose camera or select multi images
      Fluttertoast.showToast(msg: 'Upload image...');
      List _images = await imageServices.uploadIamges(assestimages);

      textEditingController.clear();
      onSendMessage(content: _images, type: 1);
    } catch (e) {
      Fluttertoast.showToast(msg: 'Upload image falid');
    }
  }

  Future<bool> onBackPress() {
    if (isShowSticker) {
      setState(() {
        isShowSticker = false;
      });
    } else {
      // Firestore.instance
      //     .collection('users')
      //     .document(currentUserId)
      //     .updateData({'chattingWith': null});
      // Navigator.pop(context);
      // Navigator.pushReplacementNamed(context, HomeScreen.routeName);
      Navigator.popUntil(context, (route) {
        return route.settings.isInitialRoute;
      });
    }

    return Future.value(false);
  }

  void _onRecorderPreesed() async {
    try {
      String result = await flutterSound.startRecorder(
        codec: t_CODEC.CODEC_AAC,
      );

      print('startRecorder: $result');

      _recorderSubscription = flutterSound.onRecorderStateChanged.listen((e) {
        DateTime date =
            new DateTime.fromMillisecondsSinceEpoch(e.currentPosition.toInt());
        String txt = DateFormat('mm:ss:SS', 'en_US').format(date);
        this.setState(() {
          this._isRecording = true;
          this._recorderTxt = txt.substring(0, 8);
          this._path = result;
        });
      });
    } catch (err) {
      print('startRecorder error: $err');
      setState(() {
        this._isRecording = false;
      });
    }
  }

  void stopRecorder() async {
    try {
      String result = await flutterSound.stopRecorder();
      print('stopRecorder: $result');

      if (_recorderSubscription != null) {
        _recorderSubscription.cancel();
        _recorderSubscription = null;
      }
      if (_dbPeakSubscription != null) {
        _dbPeakSubscription.cancel();
        _dbPeakSubscription = null;
      }
    } catch (err) {
      print('stopRecorder error: $err');
    }

    this.setState(() {
      this._isRecording = false;
    });
  }

  void onSendMessage({var content, int type, String recorderTime}) {
    // type: 0 = text, 1 = image, 2 = sticker, 3 = record
    if (type != 1 && content.trim() == '') {
      Fluttertoast.showToast(msg: 'Nothing to send');
    } else {
      textEditingController.clear();
      String timeStamp = DateTime.now().millisecondsSinceEpoch.toString();
      var documentReference = Firestore.instance
          .collection('messages')
          .document(threadId)
          .collection(threadId)
          .document(timeStamp);

      Firestore.instance.runTransaction((transaction) async {
        await transaction.set(
          documentReference,
          {
            'threadId': threadId,
            'idFrom': currentUserId,
            'idTo': selectedUser != null ? selectedUser.id : '',
            'timestamp': timeStamp,
            'content': type == 1 ? '' : content,
            'images': type == 1 ? content : [],
            'type': type,
            'nameFrom': currentUserName,
            'photoFrom': currentUserPhoto,
            'recorderTime': type == 3 ? recorderTime : ''
          },
        );
      });

      Firestore.instance.collection('threads').document(threadId).updateData({
        'lastMessage': type == 0
            ? content
            : type == 1 ? 'photo' : type == 2 ? 'sticker' : 'audio',
        'lastMessageTime': timeStamp
        //Firestore.instance.collection('messages').document(widget.threadId).collection(widget.threadId).document(timeStamp)
      });

      // listScrollController.animateTo(0.0,
      //     duration: Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      child: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              // List of messages
              buildListMessage(),

              // Sticker
              (isShowSticker ? buildSticker() : Container()),

              // Input content
              buildInput(),
            ],
          ),

          // Loading
          buildLoading()
        ],
      ),
      onWillPop: onBackPress,
    );
  }

  Widget buildSticker() {
    return Container(
      decoration: BoxDecoration(
          border: Border(top: BorderSide(color: textColor, width: 0.5)),
          color: Colors.white),
      padding: EdgeInsets.all(5.0),
      height: 180.0,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          Row(
            children: <Widget>[
              StickerImage(
                name: 'mimi1',
                onSend: onSendMessage,
              ),
              StickerImage(
                name: 'mimi2',
                onSend: onSendMessage,
              ),
              StickerImage(
                name: 'mimi3',
                onSend: onSendMessage,
              ),
            ],
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              StickerImage(
                name: 'mimi4',
                onSend: onSendMessage,
              ),
              StickerImage(
                name: 'mimi5',
                onSend: onSendMessage,
              ),
              StickerImage(
                name: 'mimi6',
                onSend: onSendMessage,
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              StickerImage(
                name: 'mimi7',
                onSend: onSendMessage,
              ),
              StickerImage(
                name: 'mimi8',
                onSend: onSendMessage,
              ),
              StickerImage(
                name: 'mimi9',
                onSend: onSendMessage,
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget buildLoading() {
    return Positioned(
      child: isLoading
          ? Container(
              child: Center(
                child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(primaryColor)),
              ),
              color: Colors.white.withOpacity(0.8),
            )
          : Container(),
    );
  }

  Widget buildListMessage() {
    return Flexible(
      child: widget.threadId == ''
          ? Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor)))
          : StreamBuilder(
              stream: Firestore.instance
                  .collection('messages')
                  .document(widget.threadId)
                  .collection(widget.threadId)
                  .orderBy('timestamp', descending: true)
                  .limit(20)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(
                      child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(primaryColor)));
                } else {
                  listMessage = snapshot.data.documents;
                  return ListView.builder(
                    padding:
                        EdgeInsets.symmetric(horizontal: 13.0, vertical: 8.0),
                    itemBuilder: (context, index) => MessageItem(
                        index: index,
                        document: listMessage[index],
                        listMessage: listMessage,
                        currentUserId: currentUserId,
                        flutterSound: flutterSound),
                    itemCount: listMessage.length,
                    reverse: true,
                    controller: listScrollController,
                  );
                }
              },
            ),
    );
  }

  Widget buildInput() {
    return Container(
        width: double.infinity,
        height: 50.0,
        decoration: BoxDecoration(
            border: Border(top: BorderSide(color: textColor, width: 0.5)),
            color: Colors.white),
        child: Stack(
          children: <Widget>[
            _buildNormalInput(),
            _isRecording ? _buildRecordingView() : SizedBox()
          ],
        ));
  }

  Widget _buildNormalInput() {
    return Row(
      children: <Widget>[
        // Button send image
        Container(
          margin: EdgeInsets.symmetric(horizontal: 1.0),
          decoration:
              BoxDecoration(color: primaryColor, shape: BoxShape.circle),
          child: IconButton(
            icon: Icon(Icons.mic),
            onPressed: _onRecorderPreesed,
            color: thirdColor,
          ),
        ),
        Container(
          margin: EdgeInsets.symmetric(horizontal: 1.0),
          child: IconButton(
            icon: Icon(Icons.image),
            onPressed: _onPickImages,
            color: primaryColor,
          ),
        ),
        Container(
          margin: EdgeInsets.symmetric(horizontal: 1.0),
          child: IconButton(
            icon: Icon(Icons.face),
            onPressed: getSticker,
            color: primaryColor,
          ),
        ),

        // Edit text
        Flexible(
          child: Container(
            child: TextField(
              style: TextStyle(color: primaryColor, fontSize: 15.0),
              controller: textEditingController,
              decoration: InputDecoration.collapsed(
                hintText: 'Type your message...',
                hintStyle: TextStyle(color: textColor),
              ),
              focusNode: focusNode,
            ),
          ),
        ),
        // Button send message
        _buildMsgBtn(
          onPreesed: () =>
              onSendMessage(content: textEditingController.text, type: 0),
        )
      ],
    );
  }

  Widget _buildRecordingView() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          FlatButton(
              child: Text(
                'Cancel',
                style: Theme.of(context)
                    .textTheme
                    .body2
                    .copyWith(color: accentColor),
              ),
              onPressed: _onRecordCancel),
          Container(
            child: Text(
              this._recorderTxt,
              style: TextStyle(
                fontSize: 27.0,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          _buildMsgBtn(onPreesed: _onSendRecord)
        ],
      ),
    );
  }

  _buildMsgBtn({Function onPreesed}) {
    return Material(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 8.0),
        child: IconButton(
          icon: Icon(Icons.send),
          onPressed: onPreesed,
          color: primaryColor,
        ),
      ),
      color: Colors.white,
    );
  }

  _onRecordCancel() {
    stopRecorder();
  }

  _onSendRecord() async {
    stopRecorder();
    File recordFile = File(_path);
    bool isExist = await recordFile.exists();

    if (isExist) {
      String fileName = DateTime.now().millisecondsSinceEpoch.toString();
      StorageReference reference =
          FirebaseStorage.instance.ref().child(fileName);

      StorageUploadTask uploadTask = reference.putFile(recordFile);
      StorageTaskSnapshot storageTaskSnapshot = await uploadTask.onComplete;

      storageTaskSnapshot.ref.getDownloadURL().then((recordUrl) {
        print('download record File: $recordUrl');
        // setState(() {
        //   isLoading = false;
        print('Recorder text: $_recorderTxt');
        onSendMessage(content: recordUrl, type: 3, recorderTime: _recorderTxt);
        Fluttertoast.showToast(msg: 'Upload record...');
        // });
      }, onError: (err) {
        // setState(() {
        //   isLoading = false;
        // });
        Fluttertoast.showToast(msg: 'This file is not an record');
      });
    }
  }
}
