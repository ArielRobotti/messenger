import Prim "mo:⛔";
import Map "mo:map/Map";
import Set "mo:map/Set";
import { nhash; n32hash; phash } "mo:map/Map";
import Text "mo:base/Text";
import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Types "types";
import GlobalTypes  "../types";
import { now } "mo:base/Time";

shared ({ caller = DEPLOYER }) actor class ChatManager() = this {

    type ChatId = Types.ChatId;
    type Chat = Types.Chat;
    type DiffusionChannel = Types.DiffusionChannel;
    type Notice = Types.Notice;
    type Participant = Types.Participant;
    type MsgContent = Types.MsgContent;
    type Msg = Types.Msg;
    type Notification = GlobalTypes.Notification;
  ////////////////////////// Variables generales ///////////////////////////////////

    let userNames = Map.new<Principal, Text>(); 
    stable let chats = Map.new<ChatId, Chat>();
    stable let diffusionChannels = Map.new<Nat, DiffusionChannel>();
    stable var lastChannelId = 0;

    stable let CANISTER_MAIN = actor(Principal.toText(DEPLOYER)):  actor {
        pushNotificationFromChatCanister: shared (Notification, [Principal]) -> async {#Ok; #Err};
    };

  ////////////////////// Main canister comunications ///////////////////////////////
    
    public shared ({ caller }) func updateUsers(arr: [{p:Principal; name: Text}]) {
        assert (caller == DEPLOYER);
        for(i in arr.vals()){ ignore Map.put<Principal, Text>(userNames, phash, i.p, i.name) }
    };

    public shared ({ caller }) func addUser(u: Principal, name: Text) {
        assert (caller == DEPLOYER);
        // ignore Set.put<Principal>(users, phash, u);
        ignore Map.put<Principal, Text>(userNames, phash, u, name)
    };

    public shared ({ caller }) func removeUser(u: Principal) {
        assert (caller == DEPLOYER);
        Map.delete<Principal, Text>(userNames, phash, u);
    };
    
    public shared ({ caller }) func iAmUser(): async Bool{
        Map.has<Principal, Text>(userNames, phash, caller);
    };

  ///////////////////////////// Private functions //////////////////////////

    func isUser(p: Principal): Bool {
        Map.has<Principal, Text>(userNames, phash, p)
    };

    func callerIncluded(c: Principal, _users: [{name: Text; principal: Principal}]): Bool{
        for(user in _users.vals()){
            if(user.principal == c) { return true }
        };
        return false
    };

    func generateDataFromUsers(users: [Principal], sender: Principal): {chatId: Nat32; sortedUsers: [Principal]; senderIndex: Nat} {
        let usersSet = Set.fromIter<Principal>(users.vals(), phash);
        let usersWithoutDuplicates = Set.toArray<Principal>(usersSet);
        let sortedUsers = Array.sort<Principal>(
            Prim.Array_tabulate<Principal>(
                usersWithoutDuplicates.size() + 1, 
                func i = if(i == 0){sender} else {usersWithoutDuplicates[i -1]}
            ),
            Principal.compare
        );
        var usersPrehash = "";
        var index = 0;
        var senderIndex = 0;
        
        for(user in (Array.sort<Principal>(sortedUsers, Principal.compare)).vals()){
            if (not Set.has<Principal>(usersSet, phash, user)) { 
                usersPrehash #= Principal.toText(user);
                if (user == sender) { senderIndex := index };
                index += 1;
            };   
        };
        let chatId = Text.hash(usersPrehash);
        {chatId; sortedUsers; senderIndex}
    };

    func getUserName(p: Principal): Text {
        switch (Map.get<Principal, Text>(userNames, phash, p)) {
            case null { "Unknown" };
            case (?name) { name }
        }
    };

    func indexOf<P> (u: P, _users: [P], equal: (P, P) -> Bool): ?Nat {
        var index = 0;
        for (user in _users.vals()){
            if (equal(user, u)) { return ?index };
            index += 1;
        };
        null;
    };

  ///////////////////////////////////// Chat /////////////////////////////////

    public shared ({ caller = principal }) func sendMsg(principalUsers: [Principal], msgContent: MsgContent ): async {#Ok: ChatId; #Err} {
        assert(isUser(principal));
        let user = Map.get<Principal, Text>(userNames, phash, principal);
        switch user {
            case null {#Err};
            case ( ?user ) {

                let {chatId; sortedUsers; senderIndex} = generateDataFromUsers(principalUsers, principal);
                let chat = Map.get<ChatId, Chat>(chats, n32hash, chatId);
                switch chat {
                    case null {
                        let users = Array.map<Principal, {name: Text; principal:Principal}>(
                            sortedUsers, 
                            func x = {name = getUserName(x); principal = x}
                        );
                        let msg = {msgContent with date = now(); sender = senderIndex; indexMsg = 0};
                        ignore Map.put<ChatId, Chat>(chats, n32hash, chatId, {users; msgs = [msg]});
                    };
                    case (?chat) {
                        let msg = {msgContent with date = now(); sender = senderIndex; indexMsg = chat.msgs.size()};
                        let updateMsgs = Prim.Array_tabulate<Msg>(
                            chat.msgs.size() + 1,
                            func i = if(i == 0) { msg } else { chat.msgs[i-1] }
                        );
                        ignore Map.put<ChatId, Chat>(chats, n32hash, chatId, {chat with msgs = updateMsgs});
                    }
                };
                let sender = {name = user; principal};
                let notification = {
                    date = now();
                    kind = #Msg({
                      sender with
                      nameSender = user;
                      chatId;} 
                    )
                };
                ignore await CANISTER_MAIN.pushNotificationFromChatCanister(notification, principalUsers);
                #Ok(chatId)
            }
        };
    };

    public shared ({ caller = principal }) func putMsgToChat(chatId: Nat32, msgContent: MsgContent): async {#Ok; #Err: Text} {
        let chat = Map.get<ChatId, Chat>(chats, n32hash, chatId);
        switch chat {
            case null { #Err("Chat not found") };
            case (?chat) {
                let senderIndex = indexOf<Principal>(
                    principal,
                    Array.map<Types.Participant, Principal>(
                        chat.users, 
                        func x = x.principal
                    ), 
                    Principal.equal          
                );
                switch senderIndex {
                    case null { return #Err("Caller not included in chat") };
                    case (?senderIndex) {
                        let msg = {msgContent with date = now(); sender = senderIndex; indexMsg = chat.msgs.size()};
                        let updateMsgs = Prim.Array_tabulate<Msg>(
                            chat.msgs.size() + 1,
                            func i = if(i == 0) { msg } else { chat.msgs[i-1] }
                        );
                        ignore Map.put<ChatId, Chat>(chats, n32hash, chatId, {chat with msgs = updateMsgs});
                        let sender = {name = chat.users[senderIndex].name; principal};
                        let notification = {
                            date = now();
                            kind = #Msg({ sender with chatId;})
                        };
                        let usersPrincipal = Array.map<{name: Text; principal:Principal}, Principal>(
                                chat.users, 
                                func x = x.principal
                        );
                        ignore await CANISTER_MAIN.pushNotificationFromChatCanister(notification, usersPrincipal);
                        #Ok
                    }
                }   
            }
        }
    };

    public shared ({ caller }) func readChat(id: ChatId): async {#Ok: Chat; #Err}{
        assert(isUser(caller));
        // TODO: Devolver chat paginado 
        let chat = Map.get<ChatId, Chat>(chats, n32hash, id);
        switch chat {
            case null { #Err };
            case ( ?chat ) {
                if (not callerIncluded(caller, chat.users)) { return #Err };
                #Ok(chat);
            }
        }
    };

    public shared ({ caller }) func readPaginateChat(id: ChatId, page: Nat): async Types.ReadChatResponse{
        let chat = Map.get<ChatId, Chat>(chats, n32hash, id);
        switch chat {
            case null { #Err("Chat not found") };
            case ( ?chat ) {
                if (not callerIncluded(caller, chat.users)) { return #Err("Caller is not included in this chat") };
                if (page == 0){
                    let length = if (chat.msgs.size() > 10) { 10 } else { chat.msgs.size()};
                    let msgs = Array.subArray<Msg>(chat.msgs, 0, length);
                    let moreMsg = chat.msgs.size() > 10;
                    return #Ok( #Start({msgs; users = chat.users; moreMsg}) )
                } else {
                    let length = if (chat.msgs.size() >= 10 * page + 10) { 10} else { chat.msgs.size() % 10};
                    let msgs = Array.subArray<Msg>(chat.msgs, 10 * page, length);
                    return #Ok( #OnlyMsgs( {msgs; moreMsg = chat.msgs.size() > 10 * page} ) )
                }
            }
        }
    };
  ///////////////////////////////// Diffusion //////////////////////////////////
    
    public shared ({ caller }) func createDiffusionChannel({users: [Participant]; name: Text; publicAccess: Bool }): async {#Ok: Nat; #Err: Text} {
        assert(isUser(caller));
        let admin = caller;
        let channel = {admin; name; users; msgs: [Notice] = []; publicAccess};
        lastChannelId += 1;
        ignore Map.put<Nat, DiffusionChannel>(diffusionChannels, nhash, lastChannelId, channel);
        #Ok(lastChannelId)
    };

    // public shared ({ caller }) func addParticipantToChannel(channelId: Nat, participant: Princip): async {
    // };

    public shared ({ caller }) func communicate({channelId: Nat; title: Text; noticeContent: MsgContent} ): async { #Ok; #Err: Text } {
        let channel = Map.get<Nat, DiffusionChannel>(diffusionChannels, nhash, channelId);
        switch channel {
            case null { #Err("Diffusion channel Error") };
            case (?channel) {
                if(caller != channel.admin) { return #Err("Caller is not admin channel") };
                let announcementsUpdate = Prim.Array_tabulate<Notice>(
                    channel.msgs.size() + 1,
                    func i = if(i == 0) { {noticeContent with date = now(); title} } else { channel.msgs[i-1] }
                );
                ignore Map.put<Nat, DiffusionChannel>(diffusionChannels, nhash, channelId, {channel with msgs = announcementsUpdate});

                let notification: Notification = { date = now(); kind = #Diffusion({channelId}) };
                ignore await CANISTER_MAIN.pushNotificationFromChatCanister(
                    notification, 
                    Array.map<Types.Participant, Principal>(
                        channel.users, 
                        func x = x.principal
                    )
                );
                return #Ok
            };
        };

    };
    
}