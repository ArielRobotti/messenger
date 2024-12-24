import Prim "mo:⛔";
import Map "mo:map/Map";
// import Set "mo:map/Set";
import { n32hash; phash } "mo:map/Map";
import Text "mo:base/Text";
import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Types "types";
import GlobalTypes  "../types";
import { now } "mo:base/Time";

shared ({ caller = DEPLOYER }) actor class ChatManager() = this {

    type ChatId = Types.ChatId;
    type Chat = Types.Chat;
    type MsgContent = Types.MsgContent;
    type Msg = Types.Msg;
    type Notification = GlobalTypes.Notification;
  ////////////////////////// Variables generales ///////////////////////////////////

    let userNames = Map.new<Principal, Text>(); 
    stable let chats = Map.new<ChatId, Chat>();
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
        let sortedUsers = Array.sort<Principal>(Prim.Array_tabulate<Principal>(
                users.size() + 1,
                func i = if(i == 0){sender} else {users[i -1]}
            ),
            Principal.compare
        );
        var usersPrehash = "";
        var index = 0;
        var senderIndex = 0;
        for(user in (Array.sort<Principal>(sortedUsers, Principal.compare)).vals()){
            usersPrehash #= Principal.toText(user);
            if (user == sender) { senderIndex := index };
            index += 1;
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

    public shared ({ caller = sender }) func sendMsg(principalUsers: [Principal], msgContent: MsgContent ): async {#Ok: ChatId; #Err} {
        assert(isUser(sender));
        let user = Map.get<Principal, Text>(userNames, phash, sender);
        switch user {
            case null {#Err};
            case ( ?user ) {

                let {chatId; sortedUsers; senderIndex} = generateDataFromUsers(principalUsers, sender);
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
                let notification = {
                    date = now();
                    kind = #Msg({
                      sender;
                      nameSender = user;
                      chatId;} 
                    )
                };
                ignore await CANISTER_MAIN.pushNotificationFromChatCanister(notification, principalUsers);
                #Ok(chatId)
            }
        };
    };

    public shared ({ caller }) func putMsgToChat(chatId: Nat32, msgContent: MsgContent): async {#Ok; #Err: Text} {
        let chat = Map.get<ChatId, Chat>(chats, n32hash, chatId);
        switch chat {
            case null { #Err("Chat not found") };
            case (?chat) {
                let senderIndex = indexOf<Principal>(
                    caller,
                    Array.map<{name: Text; principal:Principal}, Principal>(
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
                        let notification = {
                            date = now();
                            kind = #Msg({
                            sender = caller;
                            nameSender = chat.users[senderIndex].name;
                            chatId;} 
                            )
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


}