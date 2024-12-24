


module {

    public type ChatId = Nat32;

    public type UserDataInit = {
        name: Text;
        email: Text;
    };

    public let INIT_USER_VALUES = {
        contacts = [];
        chats = [];
        notifications = [];
    };

    public type User = UserDataInit and {
        contacts: [Principal];
        chats: [ChatId];
        notifications: [Notification];
    };
    public type Notification = {
        date: Int;
        kind: {
            #Msg: {nameSender: Text; sender: Principal; chatId: ChatId};
            #ContactRequest: User;
            #ContactAccepted: User
        } 
    };

}