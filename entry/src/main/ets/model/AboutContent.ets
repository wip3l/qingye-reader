export class AboutContributor {
  id: string;
  name: string;
  role: string;
  heading: string;
  message: string;

  constructor(
    id: string,
    name: string,
    role: string,
    heading: string,
    message: string
  ) {
    this.id = id;
    this.name = name;
    this.role = role;
    this.heading = heading;
    this.message = message;
  }
}

export class AboutContent {
  static readonly INTRODUCTION: string = '—— 按自己的习惯，读自己喜欢的书。';
  static readonly PROJECT_DESCRIPTION: string =
    '开源轻页是一个本地阅读工具。网页解析默认关闭，开启后仅按用户自行添加且有合法使用权限的规则，在用户设备上访问并重新排版其指定的网页。';
  static readonly COMPLIANCE_NOTICE: string =
    '本项目不内置、不托管、不分发任何小说正文、章节内容、封面图片或付费资源；不内置、不提供、不推荐任何解析规则，不提供规则订阅服务，也不维护或背书任何第三方内容站点。用户开启数据同步后，规则仅作为其私有数据保存，不公开、不能分享。';
  static readonly USAGE_NOTICE: string =
    '添加规则前，请自行确认规则来源、目标站点协议、内容授权和所在地法律法规要求。项目仅按用户配置的规则发起访问和解析，不以破解付费内容、绕过访问控制、规避反爬机制或批量抓取受保护内容为目标；由此产生的后果由用户自行承担。';

  static readonly COMPLAINT_NOTICE: string =
    '权利人认为本应用的功能被用于侵害其合法权益的，可通过本页“交流与反馈”里的邮箱联系开发者，并提供权利证明和具体情况。开发者核实后会在应用能力范围内配合处理。';

  static readonly ICON_DESIGNER: AboutContributor = new AboutContributor(
    'kuaixingxing', '@快醒醒', '新图标设计', '谢谢你，让轻页有了新的模样。',
    '感谢你为开源轻页设计新的图标。让一叠轻盈的书页，成为每次打开阅读时的美好开场。');

  static readonly CONTRIBUTORS: AboutContributor[] = [
    new AboutContributor('nanpo', '@南破万卷墙', '001 号用户 · 一路同行', '谢谢你，从第一步就同行。',
      '作为轻页的 001 号用户，你陪着这个项目一路走来。感谢这份长久的信任与陪伴，让最初的想法，慢慢长成今天的模样。'),
    new AboutContributor('erer', '@一个人吃二二', '最初的支持与建议', '起步时的鼓励，一直记在心里。',
      '感谢你在轻页起步时给予支持、分享建议。最初的每一份回应，都为继续走下去添了一份底气。'),
    new AboutContributor('captain', '@jueyaocaptain', '最初的支持与建议', '谢谢你，愿意相信最初的轻页。',
      '感谢你在轻页最初的日子里给予支持、提出建议。那些真诚的反馈，是轻页不断完善的起点，也是向前的动力。'),
    new AboutContributor('chaan', '@茶安安安', '最初的支持与建议', '最初的善意，陪轻页走到今天。',
      '感谢你在轻页起步时给予的支持与建议。在一切还很青涩的时候，你的鼓励让这段开发旅程多了一份温暖。'),
    new AboutContributor('xiangsi', '@相思界', '支持与建议 · 社区维护', '谢谢你，也照顾着这个社区。',
      '感谢你为轻页提出建议、给予支持，也用心参与社区维护。因为有你，交流多了一份温度，同行多了一份安心。'),
    new AboutContributor('yicheng', '@一程', '建设性意见与支持', '让每一个想法，再往前一步。',
      '感谢你提出有启发、有价值的建设性意见。每一次认真交流，都帮助轻页看见更好的方向，也找到继续改进的可能。'),
    new AboutContributor('bensi', '@奔四老男人', '支持与建议 · 社区维护', '谢谢你，让同行的路更踏实。',
      '感谢你一路给予支持、分享建议，并用心维护社区。让轻页更好用，也让这里成为可以安心交流的地方。'),
    new AboutContributor('jianting', '@简听阅读', '开发同行 · 相伴成长', '开发路上，有你相伴。',
      '感谢你在开发路上的陪伴与交流。从想法到实现，一路相伴、一起成长，让这段旅程多了理解，也多了继续前行的力量。')
  ];
}
