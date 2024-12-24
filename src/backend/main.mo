import Types "types";
import Map "mo:map/Map";
// import Set "mo:map/Set";
// import { now } "mo:base/Time";
import { phash} "mo:map/Map";
import Principal "mo:base/Principal";
// import Buffer "mo:base/Buffer";
import Prim "mo:⛔";
import ChatManager "./chat/chat";

// import { print } "mo:base/Debug";
// import Array "mo:base/Array";
// import Blob "mo:base/Blob";
// import Nat8 "mo:base/Nat8";
// import Nat "mo:base/Nat";
import Text "mo:base/Text";

actor {

    type UserDataInit = Types.UserDataInit;
    type User = Types.User;

    stable let users = Map.new<Principal, User>();
    stable var CHAT_MANAGER: ChatManager.ChatManager = actor("aaaaa-aa");
    stable let notifications = Map.new<Principal, [Types.Notification]>();


    func deployChatCanister(): async Principal {
        assert(Principal.fromActor(CHAT_MANAGER) == Principal.fromText("aaaaa-aa"));
        Prim.cyclesAdd<system>(200_000_000_000);
        CHAT_MANAGER := await ChatManager.ChatManager();
        Principal.fromActor(CHAT_MANAGER);
    };

    public shared ({ caller }) func initChat(): async Principal{
        assert(Principal.isController(caller));
        await deployChatCanister()
    };

    public query func getChatCanisterId(): async Text {
        Principal.toText(Principal.fromActor(CHAT_MANAGER))
    };
  /////////////////////////////  Users functions //////////////////////////

    public shared ({ caller }) func signUp(init: UserDataInit): async {#Ok; #Err: Text}{
        if(Map.has<Principal, User>(users, phash, caller)){
        return #Err("Caller is already user");
        };
        let newUser: User = { init and Types.INIT_USER_VALUES};
        ignore Map.put<Principal, User>(users, phash, caller, newUser );
        CHAT_MANAGER.addUser(caller, init.name);
        #Ok
    };

    public shared ({ caller }) func signIn(): async ?User{
        Map.get<Principal, User>(users, phash, caller);
    };

  /////////////////////// Chat Canister comunications ////////////////////

    public shared ({ caller }) func pushNotificationFromChatCanister(notif: Types.Notification, users: [Principal]): async {#Ok; #Err}{
        assert(caller == Principal.fromActor(CHAT_MANAGER));
        for(user in users.vals()){
            let userNotifications = switch (Map.get<Principal, [Types.Notification]>(notifications, phash, user)) {
                case null {[notif]};
                case (?userNotifications){
                    Prim.Array_tabulate<Types.Notification>(
                        userNotifications.size() + 1, 
                        func i = if(i == 0){notif} else {userNotifications[i - 1]})
                    }
                };
            ignore Map.put<Principal, [Types.Notification]>(notifications, phash, user, userNotifications);
        };
        #Ok
    };

    public shared ({ caller }) func getNotifications(): async [Types.Notification]{
        switch (Map.get<Principal, [Types.Notification]>(notifications, phash, caller)){
            case null {[]};
            case (?userNotifications) {userNotifications}
        }
    };

    



  
  
};
